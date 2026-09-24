"""Turning a store's webhook into an account's plan.

**Nothing here can charge anybody.** Google takes the money; RevenueCat watches
Google and tells us what changed. All this does is read "this account has the
`plus` entitlement until Tuesday" and write it down. There is no card, no
payment call, and no way for a bug in this file to move money.

What a bug here *can* do is give away access, or take away access somebody paid
for. So the rules are:

* **Only a verified event changes a plan.** The app is never believed.
* **Every event is applied at most once.** Stores deliver more than once, and
  a webhook that arrives twice must not extend anything twice.
* **Arrival order means nothing.** What matters is which period an event is
  about. A stale event must never shorten a plan that has since been renewed.
* **Refunds take effect at once.** Everything else can wait for a period to end.
"""

import hmac
import logging
from dataclasses import dataclass
from datetime import UTC, datetime

import psycopg

from app.core import config
from app.services import db, plans

log = logging.getLogger("carry.billing")


class NotOurs(Exception):
    """The event didn't come with our secret, so it isn't ours to act on."""


class NotConfigured(Exception):
    """No webhook secret, so no event can be trusted. Refuse them all."""


#: Events that mean "this account has the entitlement now".
_GRANTS = {
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "PRODUCT_CHANGE",
    "SUBSCRIPTION_EXTENDED",
    "NON_RENEWING_PURCHASE",
}

#: Events that end it. `EXPIRATION` only if the period we hold has run out;
#: `CANCELLATION` with a refund is immediate, because the money went back.
_ENDS = {"EXPIRATION", "REFUND"}


@dataclass(frozen=True)
class Event:
    """The part of a RevenueCat webhook we act on."""

    id: str
    kind: str
    uid: str | None
    entitlements: tuple[str, ...]
    #: End of the period this event is about. None when it doesn't say.
    period_end: datetime | None
    #: For TRANSFER: the account losing it, and the one gaining it.
    from_uid: str | None = None
    to_uid: str | None = None

    @property
    def grants_plus(self) -> bool:
        """Entitlement, never product.

        Products change — a yearly plan, a price rise, a regional SKU — and
        code that checks a product breaks the day one is added.
        """
        return plans.PLUS_ENTITLEMENT in self.entitlements


def check_secret(sent: str | None) -> None:
    """Raises unless the caller knows the secret RevenueCat was given.

    Compared in constant time: a plain `==` leaks how much of the secret was
    right through how long the comparison took, which is enough to guess it a
    character at a time.
    """
    expected = config.REVENUECAT_WEBHOOK_SECRET
    if not expected:
        raise NotConfigured(
            "No REVENUECAT_WEBHOOK_SECRET, so no billing event can be trusted."
        )
    if not sent or not hmac.compare_digest(sent, expected):
        raise NotOurs("bad or missing webhook secret")


def read(payload: dict) -> Event:
    """Pulls what we need out of a RevenueCat webhook body.

    Anything missing is a refusal, not a guess: an event we can't read is an
    event we must not act on.
    """
    if not isinstance(payload, dict):
        # Valid JSON, but a list or a bare string. `.get` on one of those is an
        # AttributeError, which is a 500 - and this is a refusal, not a bug.
        raise ValueError("payload is not an object")
    event = payload.get("event")
    if not isinstance(event, dict):
        raise ValueError("no event in the payload")
    event_id = event.get("id")
    kind = event.get("type")
    if not event_id or not kind:
        raise ValueError("event has no id or type")

    entitlements = event.get("entitlement_ids") or []
    if not isinstance(entitlements, list):
        raise ValueError("entitlement_ids is not a list")

    return Event(
        id=str(event_id),
        kind=str(kind),
        uid=_text(event.get("app_user_id")),
        entitlements=tuple(str(e) for e in entitlements),
        period_end=_moment(event.get("expiration_at_ms")),
        from_uid=_side(event.get("transferred_from")),
        to_uid=_side(event.get("transferred_to")),
    )


def apply(event: Event) -> bool:
    """Applies an event to an account. True if it was new, False if a repeat.

    The whole thing runs in one transaction: the ledger row and the plan change
    land together or not at all, so a crash between them can't leave an event
    recorded as applied that never was.
    """
    try:
        with db.connection() as conn, conn.transaction():
            if not _remember(conn, event):
                log.info("billing event %s already applied", event.id)
                return False
            _apply_to_account(conn, event)
            return True
    except psycopg.Error as e:
        raise db.Unavailable(f"billing.apply failed: {e}") from e


def _remember(conn, event: Event) -> bool:
    """Writes the event to the ledger. False when it was already there.

    `ON CONFLICT DO NOTHING` and then checking what came back: the primary key
    does the deciding, so two copies of the same webhook arriving at once can't
    both win.
    """
    row = conn.execute(
        """
        INSERT INTO billing_events (event_id, uid, kind)
        VALUES (%s, %s, %s)
        ON CONFLICT (event_id) DO NOTHING
        RETURNING event_id
        """,
        (event.id, event.uid, event.kind),
    ).fetchone()
    return row is not None


def _apply_to_account(conn, event: Event) -> None:
    if event.kind == "TRANSFER":
        _transfer(conn, event)
        return

    uid = event.uid
    if not uid:
        log.warning("billing event %s has no account", event.id)
        return

    if event.kind in _GRANTS and event.grants_plus:
        _grant(conn, uid, event.period_end)
    elif event.kind in _ENDS:
        _end(conn, uid, event)
    elif event.kind in {"CANCELLATION", "BILLING_ISSUE", "SUBSCRIPTION_PAUSED"}:
        # They keep what they paid for until it runs out. Cancelling is a
        # decision about the *next* period, and a failed payment is something
        # the store retries for days.
        log.info("%s for %s: keeping the plan until it expires", event.kind, uid)
    else:
        log.info("billing event %s (%s): nothing to do", event.id, event.kind)


def _grant(conn, uid: str, until: datetime | None) -> None:
    """Gives the plan, if the event is one we can act on.

    Three refusals, each of which was a way to hand out access that shouldn't
    have been handed out:

    * **No end date, no grant.** A grant with nothing to expire is a plan that
      never ends, which is not something Carry sells.
    * **A period that already ended grants nothing.** A delayed renewal for
      last month must not restore access that has since been taken away — with
      `plan_until` cleared there is nothing left to compare it against.
    * **The longest period wins**, so an old event can't shorten a newer one.

    Written as an upsert because the webhook can arrive before the account's
    first request. An UPDATE would change no row, the event would be recorded
    as applied, and somebody would have paid for nothing with no way to replay
    it.
    """
    if until is None:
        log.warning("grant for %s has no end date, ignoring it", uid)
        return
    if until <= datetime.now(UTC):
        log.info("grant for %s is for a period that already ended", uid)
        return
    conn.execute(
        """
        INSERT INTO users (uid, plan, plan_source, plan_until)
        VALUES (%s, %s, 'play', %s)
        ON CONFLICT (uid) DO UPDATE
            SET plan = EXCLUDED.plan,
                plan_source = 'play',
                plan_until = GREATEST(
                    EXCLUDED.plan_until,
                    COALESCE(users.plan_until, EXCLUDED.plan_until)
                )
        """,
        (uid, plans.PLUS, until),
    )


def _end(conn, uid: str, event: Event) -> None:
    """Takes the plan away, when it is really over.

    Both kinds of ending ask the same question — *is this about the period we
    are holding?* — because both can arrive late:

    * a stale `EXPIRATION` after a newer renewal would revoke a plan that has
      since been paid for;
    * a refund of **last** month, arriving after this month was paid for,
      would do exactly the same.

    A refund with no period at all is the one case that still revokes: money
    going back is an explicit signal, it is rare, and reconciliation will put
    it right if the store meant otherwise.
    """
    if event.kind == "REFUND" and event.period_end is None:
        log.warning("refund for %s has no period, revoking anyway", uid)
        conn.execute(
            "UPDATE users SET plan = %s, plan_until = NULL WHERE uid = %s",
            (plans.FREE, uid),
        )
        return

    conn.execute(
        """
        UPDATE users
           SET plan = %s, plan_until = NULL
         WHERE uid = %s
           AND (plan_until IS NULL OR plan_until <= %s)
        """,
        (plans.FREE, uid, event.period_end or datetime.now(UTC)),
    )


def _transfer(conn, event: Event) -> None:
    """Moves a plan from one account to another.

    One Play account, two Google logins: the store moves the entitlement, and
    if we only added it to the new account the old one would keep a plan
    nobody is paying for. It has to move, not copy.

    The source row is locked before it is read. Without that, two transfers
    from the same account can both see Plus and both hand it out — the
    transaction makes each one atomic without stopping the plan being copied.

    A plan we granted by hand is left alone: it isn't the subscription being
    transferred, taking it away would punish the wrong person, and there is
    nothing for the destination either - the date on that row belongs to the
    grant, which stays put.
    """
    if not event.from_uid or not event.to_uid:
        # Either a side named nobody we know, or it named two accounts and
        # there was no way to choose. Both mean paid access may now be sitting
        # on the wrong account, and neither is something a redelivery of the
        # same payload would fix, so it goes on the list for a person.
        log.warning("transfer %s does not name one account on each side", event.id)
        _flag(conn, event.id, "transfer did not name one account on each side")
        return
    row = conn.execute(
        "SELECT plan, plan_until, plan_source FROM users WHERE uid = %s FOR UPDATE",
        (event.from_uid,),
    ).fetchone()
    if row is None or row[0] == plans.FREE:
        log.info("transfer %s: nothing to move", event.id)
        return
    # A transfer event carries no period of its own. RevenueCat's TRANSFER
    # payload is only `transferred_from` and `transferred_to` - no product, no
    # expiry - so the source row's date is all there is, and it is the right
    # one: a transfer moves every transaction on that store account, leaving
    # nothing behind that could still own the date.
    #
    # Only a plan the store paid for is the store's to take away. A plan we
    # granted by hand isn't the subscription being transferred, so it stays
    # where it is, and there is nothing for the destination either.
    if row[2] != "play":
        log.info(
            "transfer %s: %s on %s was granted by hand, leaving it",
            event.id,
            row[0],
            event.from_uid,
        )
        return
    until = row[1]
    if until is None or until <= datetime.now(UTC):
        # Undated or already over: nothing live to hand on, and clearing the
        # source would only take away a plan that has expired anyway.
        log.info("transfer %s: nothing live to move from %s", event.id, event.from_uid)
        return

    conn.execute(
        "UPDATE users SET plan = %s, plan_until = NULL, plan_source = NULL"
        " WHERE uid = %s",
        (plans.FREE, event.from_uid),
    )
    _grant(conn, event.to_uid, until)
    log.info("moved %s from %s to %s", row[0], event.from_uid, event.to_uid)


def _flag(conn, event_id: str, problem: str) -> None:
    """Leaves a note on the ledger row for a human to find.

    Same transaction as everything else, so the note and the event arrive
    together. See the `problem` column in db.py for how to read the list.
    """
    conn.execute(
        "UPDATE billing_events SET problem = %s WHERE event_id = %s",
        (problem, event_id),
    )


def _text(value) -> str | None:
    return str(value) if value else None


# What the store calls somebody before they sign in. Those IDs name nobody
# here: our accounts are keyed by Firebase uid.
ANONYMOUS = "$RCAnonymousID:"


def _side(value) -> str | None:
    """One end of a transfer.

    RevenueCat sends each side as an *array* of app user IDs, not a string -
    one customer can have several, the anonymous one the store issued before
    they signed in and then ours. Only ours names an account, so the anonymous
    ones are dropped, and the rest deduplicated: the same account named twice
    is one account, and treating it as two would send a transfer we could have
    applied off to be sorted out by hand.

    If that still leaves more than one there is no way to choose between them,
    and inventing an answer would either strand a subscription or hand it to
    the wrong account, so we take none and leave a note for a person.
    """
    ids = value if isinstance(value, list) else [value]
    # dict.fromkeys, not a set: which one is left matters when there is one,
    # and a set's order is not the payload's.
    ours = list(
        dict.fromkeys(str(i) for i in ids if i and not str(i).startswith(ANONYMOUS))
    )
    if len(ours) > 1:
        log.warning("a transfer names %d accounts on one side; leaving it", len(ours))
        return None
    return ours[0] if ours else None


def _moment(millis) -> datetime | None:
    """RevenueCat sends times as milliseconds since the epoch."""
    if millis is None:
        return None
    try:
        return datetime.fromtimestamp(int(millis) / 1000, tz=UTC)
    except (TypeError, ValueError, OverflowError, OSError):
        return None
