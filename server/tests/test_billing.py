"""Turning a store's webhook into a plan, carefully.

Nothing here can charge anyone — Google takes the money and RevenueCat reports
it. What a bug here *can* do is give away access, or take away access somebody
paid for, so these are the cases that do that.
"""

from datetime import UTC, datetime, timedelta

import pytest

from app.core import config
from app.services import billing, plans

SECRET = "a-shared-secret"
# Two periods that are still running, and stay that way: a fixed date would
# quietly become "already expired" once it passed, and every test that means
# "still paid for" would start passing for the wrong reason. Whole seconds,
# because the payload carries milliseconds and anything finer than that would
# not survive the round trip.
_NOW = datetime.now(UTC).replace(microsecond=0)
LATER = _NOW + timedelta(days=60)
SOONER = _NOW + timedelta(days=30)


def event(
    kind: str = "INITIAL_PURCHASE",
    event_id: str = "evt-1",
    uid: str | None = "ada",
    entitlements: list[str] | None = None,
    ends: datetime | None = LATER,
    **extra,
) -> dict:
    """A RevenueCat webhook body, as it arrives."""
    body = {
        "id": event_id,
        "type": kind,
        "app_user_id": uid,
        "entitlement_ids": ["plus"] if entitlements is None else entitlements,
        "expiration_at_ms": int(ends.timestamp() * 1000) if ends else None,
    }
    # The store names the two ends of a transfer as arrays, so the tests do
    # too: a helper that sends a plain string would be testing a payload that
    # never arrives.
    for side in ("transferred_from", "transferred_to"):
        if side in extra and not isinstance(extra[side], list):
            extra[side] = [extra[side]]
    body.update(extra)
    return {"event": body}


class TestTheSecret:
    """Open to the internet, so the secret is the only thing that makes an
    event ours."""

    def test_the_right_secret_is_accepted(self, monkeypatch):
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)

        billing.check_secret(SECRET)  # must not raise

    @pytest.mark.parametrize("sent", [None, "", "wrong", SECRET + "x", SECRET[:-1]])
    def test_anything_else_is_refused(self, sent, monkeypatch):
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)

        with pytest.raises(billing.NotOurs):
            billing.check_secret(sent)

    def test_no_secret_configured_refuses_everything(self, monkeypatch):
        """Fail closed. A server with no secret cannot tell a real event from
        someone asking for a free subscription."""
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "")

        with pytest.raises(billing.NotConfigured):
            billing.check_secret("anything")


class TestReadingTheEvent:
    def test_the_parts_we_act_on(self):
        read = billing.read(event(ends=LATER))

        assert read.id == "evt-1"
        assert read.kind == "INITIAL_PURCHASE"
        assert read.uid == "ada"
        assert read.period_end == LATER
        assert read.grants_plus is True

    def test_entitlements_decide_it_not_products(self):
        """A product id says which SKU was bought; an entitlement says what
        they may do. Products change and entitlements don't."""
        bought_something_else = billing.read(
            event(entitlements=["pro_annual_v2"], product_id="carry_plus_monthly")
        )

        assert bought_something_else.grants_plus is False

    @pytest.mark.parametrize(
        "payload",
        [
            {},
            [],  # valid JSON, but not an object
            "an event, honest",
            {"event": None},
            {"event": {"type": "RENEWAL"}},  # no id
            {"event": {"id": "e"}},  # no type
            {"event": {"id": "e", "type": "RENEWAL", "entitlement_ids": "plus"}},
        ],
    )
    def test_an_event_we_cannot_read_is_refused_not_guessed(self, payload):
        with pytest.raises(ValueError):
            billing.read(payload)

    def test_a_nonsense_expiry_is_no_expiry_rather_than_a_crash(self):
        read = billing.read(event(**{"expiration_at_ms": "soon-ish"}))

        assert read.period_end is None


class _FakeCursor:
    def __init__(self, row):
        self.row = row

    def fetchone(self):
        return self.row


class FakeDatabase:
    """Enough of Postgres to watch what billing does to an account."""

    def __init__(self, accounts: dict[str, dict] | None = None):
        self.accounts = accounts or {}
        self.events: set[str] = set()
        self.problems: dict[str, str] = {}
        self.statements: list[str] = []

    # -- what the code calls ------------------------------------------------
    def execute(self, sql, params=None):
        flat = " ".join(sql.split())
        self.statements.append(flat)
        if flat.startswith("INSERT INTO billing_events"):
            event_id = params[0]
            if event_id in self.events:
                return _FakeCursor(None)  # the primary key refused it
            self.events.add(event_id)
            return _FakeCursor((event_id,))
        if flat.startswith("UPDATE billing_events SET problem"):
            self.problems[params[1]] = params[0]
            return _FakeCursor(None)
        if flat.startswith("INSERT INTO users"):
            self._upsert(params)
            return _FakeCursor(None)
        if flat.startswith("SELECT plan, plan_until, plan_source FROM users"):
            account = self.accounts.get(params[0])
            if account is None:
                return _FakeCursor(None)
            return _FakeCursor(
                (account["plan"], account["plan_until"], account.get("source"))
            )
        if flat.startswith("UPDATE users"):
            self._update(flat, params)
            return _FakeCursor(None)
        raise AssertionError(f"unexpected statement: {flat}")

    def _upsert(self, params):
        """A grant: created if new, and the longest period wins if not."""
        uid, plan, until = params
        account = self.accounts.get(uid)
        if account is None:
            self.accounts[uid] = {"plan": plan, "plan_until": until, "source": "play"}
            return
        held = account["plan_until"]
        account.update(
            plan=plan,
            source="play",
            plan_until=max(until, held) if held and until else until,
        )

    def _update(self, sql, params):
        if "plan_until <= %s" in sql:  # an expiry, or a dated refund
            uid, ended_by = params[1], params[2]
            account = self.accounts.get(uid)
            if account and (
                account["plan_until"] is None or account["plan_until"] <= ended_by
            ):
                account.update(plan=params[0], plan_until=None)
            return
        if "plan_source = NULL" in sql:  # the losing side of a move
            uid = params[1]
            if uid in self.accounts:
                self.accounts[uid].update(
                    plan=params[0], plan_until=None, source=None
                )
            return
        # An undated refund.
        uid = params[1]
        if uid in self.accounts:
            self.accounts[uid].update(plan=params[0], plan_until=None)

    # -- what `with db.connection()` needs ----------------------------------
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def transaction(self):
        return self


@pytest.fixture
def database(monkeypatch):
    def make(accounts=None):
        fake = FakeDatabase(accounts)
        monkeypatch.setattr(billing.db, "connection", lambda: fake)
        return fake

    return make


class TestApplying:
    def test_a_purchase_grants_the_plan(self, database):
        db = database(
            {"ada": {"plan": "free", "plan_until": None, "source": None}}
        )

        assert billing.apply(billing.read(event())) is True
        assert db.accounts["ada"]["plan"] == plans.PLUS
        assert db.accounts["ada"]["plan_until"] == LATER

    def test_the_same_event_twice_is_applied_once(self, database):
        """Stores deliver webhooks more than once. The second must change
        nothing at all."""
        db = database(
            {"ada": {"plan": "free", "plan_until": None, "source": None}}
        )
        first = billing.apply(billing.read(event(event_id="evt-7")))

        second = billing.apply(billing.read(event(event_id="evt-7")))

        assert (first, second) == (True, False)
        touched = [
            s
            for s in db.statements
            if s.startswith(("UPDATE users", "INSERT INTO users"))
        ]
        assert len(touched) == 1

    def test_an_event_without_the_entitlement_grants_nothing(self, database):
        db = database(
            {"ada": {"plan": "free", "plan_until": None, "source": None}}
        )

        billing.apply(billing.read(event(entitlements=[])))

        assert db.accounts["ada"]["plan"] == "free"

    def test_an_old_renewal_cannot_shorten_a_newer_one(self, database):
        """Webhooks arrive out of order. The longest period we have heard
        about wins."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(billing.read(event(event_id="old", kind="RENEWAL", ends=SOONER)))

        assert db.accounts["ada"]["plan_until"] == LATER

    def test_cancelling_keeps_the_plan_until_it_runs_out(self, database):
        """They paid for this period. Cancelling is a decision about the next
        one."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(billing.read(event(event_id="c", kind="CANCELLATION")))

        assert db.accounts["ada"]["plan"] == plans.PLUS
        assert db.accounts["ada"]["plan_until"] == LATER

    def test_a_billing_issue_keeps_it_too(self, database):
        """The store retries a failed card for days. Dropping someone to free
        the moment a renewal fails would be wrong most of the time."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(billing.read(event(event_id="b", kind="BILLING_ISSUE")))

        assert db.accounts["ada"]["plan"] == plans.PLUS

    def test_an_expiry_for_the_period_we_hold_ends_it(self, database):
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": SOONER, "source": "play"}}
        )

        billing.apply(
            billing.read(event(event_id="x", kind="EXPIRATION", ends=SOONER))
        )

        assert db.accounts["ada"]["plan"] == plans.FREE
        assert db.accounts["ada"]["plan_until"] is None

    def test_but_a_stale_expiry_cannot_revoke_a_renewed_plan(self, database):
        """The trap. An old EXPIRATION arriving after a newer RENEWAL would
        otherwise take away a plan that has since been paid for."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(
            billing.read(event(event_id="stale", kind="EXPIRATION", ends=SOONER))
        )

        assert db.accounts["ada"]["plan"] == plans.PLUS
        assert db.accounts["ada"]["plan_until"] == LATER

    def test_a_refund_ends_it_at_once(self, database):
        """The money went back, so the access goes with it - no waiting for a
        period to end."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(billing.read(event(event_id="r", kind="REFUND")))

        assert db.accounts["ada"]["plan"] == plans.FREE
        assert db.accounts["ada"]["plan_until"] is None


class TestThingsIDidNotThinkOf:
    """The cases review found, which my own tests had no opinion about.

    All of them are the same shape: an event arriving when the account is in a
    state I hadn't pictured.
    """

    def test_a_grant_with_no_end_date_grants_nothing(self, database):
        """A plan that never expires is not something Carry sells, and an
        event that forgot to say when is not a licence to invent one."""
        db = database(
            {"ada": {"plan": "free", "plan_until": None, "source": None}}
        )

        billing.apply(billing.read(event(event_id="undated", ends=None)))

        assert db.accounts["ada"]["plan"] == plans.FREE

    def test_a_grant_for_a_period_that_already_ended_grants_nothing(self, database):
        """A renewal delayed past its own period would otherwise restore
        access that expiry had already taken away - there is no stored end
        date left to compare it against."""
        gone = datetime.now(UTC) - timedelta(days=40)
        db = database(
            {"ada": {"plan": "free", "plan_until": None, "source": None}}
        )

        billing.apply(
            billing.read(event(event_id="late", kind="RENEWAL", ends=gone))
        )

        assert db.accounts["ada"]["plan"] == plans.FREE

    def test_a_purchase_before_the_account_exists_still_lands(self, database):
        """The webhook can beat the account's first request. An UPDATE would
        change no row, the event would be marked applied, and somebody would
        have paid for nothing with no way to replay it."""
        db = database({})  # nobody has ever called /me

        billing.apply(billing.read(event(uid="brand-new")))

        assert db.accounts["brand-new"]["plan"] == plans.PLUS

    def test_a_stale_refund_cannot_revoke_a_renewed_plan(self, database):
        """The same trap as a stale expiry, which I had tested - and then did
        not apply to refunds."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(
            billing.read(event(event_id="old-refund", kind="REFUND", ends=SOONER))
        )

        assert db.accounts["ada"]["plan"] == plans.PLUS

    def test_a_refund_with_no_period_still_revokes(self, database):
        """Money going back is an explicit signal, and reconciliation is the
        backstop if the store meant something else."""
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(
            billing.read(event(event_id="undated-refund", kind="REFUND", ends=None))
        )

        assert db.accounts["ada"]["plan"] == plans.FREE


class TestTransfer:
    """One Play account, two Google logins: the store moves the entitlement,
    and so must we. Copying it would leave a plan nobody is paying for."""

    def test_the_plan_moves_rather_than_being_copied(self, database):
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to="grace",
                )
            )
        )

        assert db.accounts["grace"]["plan"] == plans.PLUS
        assert db.accounts["grace"]["plan_until"] == LATER
        assert db.accounts["ada"]["plan"] == plans.FREE

    def test_transferring_nothing_changes_nothing(self, database):
        db = database(
            {
                "ada": {"plan": plans.FREE, "plan_until": None, "source": None},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t2",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to="grace",
                )
            )
        )

        assert db.accounts["grace"]["plan"] == plans.FREE

    def test_a_plan_we_granted_by_hand_is_left_alone(self, database):
        """A store transfer is about a subscription. Taking away a plan we
        gave someone would punish the wrong person for somebody else's
        second Google login."""
        db = database(
            {
                "ada": {
                    "plan": plans.PLUS,
                    "plan_until": LATER,
                    "source": "granted",
                },
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t4",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to="grace",
                )
            )
        )

        # The manual grant stays where it was...
        assert db.accounts["ada"]["plan"] == plans.PLUS
        # ...and nothing is invented for the destination. The date on that row
        # belongs to the grant, which didn't move.
        assert db.accounts["grace"]["plan"] == plans.FREE

    def test_the_period_comes_from_the_source_not_the_event(self, database):
        """A TRANSFER payload is `transferred_from` and `transferred_to` and
        nothing else - no expiry. Anything a period field happens to hold on
        one is not the subscription's, so the source row decides."""
        db = database(
            {
                "ada": {
                    "plan": plans.PLUS,
                    "plan_until": SOONER,
                    "source": "play",
                },
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t6",
                    kind="TRANSFER",
                    uid=None,
                    ends=LATER,
                    transferred_from="ada",
                    transferred_to="grace",
                )
            )
        )

        assert db.accounts["grace"]["plan_until"] == SOONER

    def test_a_stale_event_period_does_not_stop_the_move(self, database):
        """The source's subscription is live; a date on the event is not the
        subscription's and must not be allowed to strand it on the account it
        has left."""
        gone = datetime.now(UTC) - timedelta(days=10)
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t7",
                    kind="TRANSFER",
                    uid=None,
                    ends=gone,
                    transferred_from="ada",
                    transferred_to="grace",
                )
            )
        )

        assert db.accounts["ada"]["plan"] == plans.FREE
        assert db.accounts["grace"]["plan"] == plans.PLUS
        assert db.accounts["grace"]["plan_until"] == LATER

    def test_a_period_that_has_already_ended_moves_nothing(self, database):
        """The source's plan ran out before the transfer arrived. There is no
        access left to hand over, so the destination is given none."""
        gone = datetime.now(UTC) - timedelta(days=10)
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": gone, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t8",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to="grace",
                )
            )
        )

        assert db.accounts["grace"]["plan"] == plans.FREE

    def test_the_anonymous_id_the_store_made_is_not_an_account(self, database):
        """Before somebody signs in the store calls them $RCAnonymousID:...,
        and both ends of a transfer can carry those alongside ours. Ours is
        the only one that names an account here."""
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t9",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from=["$RCAnonymousID:9f3c", "ada"],
                    transferred_to=["$RCAnonymousID:1b7e", "grace"],
                )
            )
        )

        assert db.accounts["ada"]["plan"] == plans.FREE
        assert db.accounts["grace"]["plan"] == plans.PLUS

    def test_two_accounts_on_one_side_move_nothing(self, database):
        """There is no way to tell which of them the subscription belongs to.
        Guessing would either strand it or hand it to the wrong person, so
        nothing moves and reconciliation settles it."""
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
                "hopper": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t10",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to=["grace", "hopper"],
                )
            )
        )

        assert db.accounts["ada"]["plan"] == plans.PLUS
        assert db.accounts["grace"]["plan"] == plans.FREE
        assert db.accounts["hopper"]["plan"] == plans.FREE

    def test_a_transfer_we_cannot_read_is_left_for_a_person(self, database):
        """Acknowledging is right - the store would only redeliver the same
        payload - but paid access may now be on the wrong account, so it goes
        on the list somebody can actually query."""
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )

        assert billing.apply(
            billing.read(
                event(
                    event_id="t11",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to=["grace", "hopper"],
                )
            )
        )

        assert "one account on each side" in db.problems["t11"]
        assert db.accounts["ada"]["plan"] == plans.PLUS  # nothing was lost

    def test_the_plan_cannot_be_moved_twice(self, database):
        """Two transfers from one account would otherwise both see Plus and
        both hand it out. The second finds nothing left to move."""
        db = database(
            {
                "ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"},
                "grace": {"plan": plans.FREE, "plan_until": None, "source": None},
                "hopper": {"plan": plans.FREE, "plan_until": None, "source": None},
            }
        )
        move = lambda to, at: billing.apply(  # noqa: E731 - a test shorthand
            billing.read(
                event(
                    event_id=f"t-{to}",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to=to,
                )
            )
        )

        move("grace", LATER)
        move("hopper", LATER)

        assert db.accounts["grace"]["plan"] == plans.PLUS
        assert db.accounts["hopper"]["plan"] == plans.FREE

    def test_a_transfer_to_an_account_that_does_not_exist_yet_lands(self, database):
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(
            billing.read(
                event(
                    event_id="t5",
                    kind="TRANSFER",
                    uid=None,
                    transferred_from="ada",
                    transferred_to="brand-new",
                )
            )
        )

        assert db.accounts["brand-new"]["plan"] == plans.PLUS

    def test_a_transfer_missing_an_account_is_ignored(self, database):
        db = database(
            {"ada": {"plan": plans.PLUS, "plan_until": LATER, "source": "play"}}
        )

        billing.apply(
            billing.read(
                event(event_id="t3", kind="TRANSFER", uid=None, transferred_from="ada")
            )
        )

        assert db.accounts["ada"]["plan"] == plans.PLUS


class TestTheEndpoint:
    def test_a_webhook_with_the_secret_is_applied(self, client, monkeypatch):
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)
        applied = []
        monkeypatch.setattr(billing, "apply", lambda e: applied.append(e) or True)

        res = client.post(
            "/billing/webhook", json=event(), headers={"Authorization": SECRET}
        )

        assert res.status_code == 204
        assert applied[0].uid == "ada"

    def test_without_the_secret_it_is_refused(self, client, monkeypatch):
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)
        monkeypatch.setattr(
            billing, "apply", lambda e: pytest.fail("applied an unverified event")
        )

        res = client.post("/billing/webhook", json=event())

        assert res.status_code == 401

    def test_a_body_that_is_not_an_event_is_a_400(self, client, monkeypatch):
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)

        res = client.post(
            "/billing/webhook", json={"hello": True}, headers={"Authorization": SECRET}
        )

        assert res.status_code == 400

    def test_a_body_that_is_not_json_at_all_is_a_400(self, client, monkeypatch):
        """A truncated delivery, or somebody poking at the endpoint. Without a
        status we chose, `request.json()` raises and it is a 500 that reads
        like Carry broke."""
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)

        res = client.post(
            "/billing/webhook",
            content=b"not json at all",
            headers={"Authorization": SECRET, "Content-Type": "application/json"},
        )

        assert res.status_code == 400

    def test_a_body_that_is_json_but_not_an_object_is_a_400(
        self, client, monkeypatch
    ):
        """`[].get("event")` is an AttributeError, and an unhandled one is a
        500."""
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)

        res = client.post(
            "/billing/webhook", json=["nope"], headers={"Authorization": SECRET}
        )

        assert res.status_code == 400

    def test_a_database_blip_asks_the_store_to_send_it_again(
        self, client, monkeypatch
    ):
        """A 503 means RevenueCat retries. Swallowing it would lose a payment
        somebody made."""
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", SECRET)

        def unavailable(_event):
            raise billing.db.Unavailable("neon is asleep")

        monkeypatch.setattr(billing, "apply", unavailable)

        res = client.post(
            "/billing/webhook", json=event(), headers={"Authorization": SECRET}
        )

        assert res.status_code == 503

    def test_a_server_with_no_secret_refuses_rather_than_trusts(
        self, client, monkeypatch
    ):
        monkeypatch.setattr(config, "REVENUECAT_WEBHOOK_SECRET", "")

        res = client.post(
            "/billing/webhook", json=event(), headers={"Authorization": "anything"}
        )

        assert res.status_code == 503
