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
        from_uid=_text(event.get("transferred_from")),
        to_uid=_text(event.get("transferred_to")),
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
    """Gives the plan, but never shortens one that already runs longer.

    Webhooks arrive out of order. An old renewal landing after a newer one must
    not pull somebody's expiry backwards, so the longest period we have heard
    about wins.
    """
    conn.execute(
        """
        UPDATE users
           SET plan = %s,
               plan_source = 'play',
               plan_until = GREATEST(%s, COALESCE(plan_until, %s))
         WHERE uid = %s
        """,
        (plans.PLUS, until, until, uid),
    )


def _end(conn, uid: str, event: Event) -> None:
    """Takes the plan away, when it is really over.

    A refund is immediate: the money went back, so the access goes with it.

    An expiry is a question, not an instruction — *has the period we hold
    ended?* An old `EXPIRATION` arriving after a newer renewal would otherwise
    revoke a plan that has since been paid for, which is the kind of thing you
    hear about from the one customer it happened to.
    """
    if event.kind == "REFUND":
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
    """
    if not event.from_uid or not event.to_uid:
        log.warning("transfer %s is missing an account", event.id)
        return
    row = conn.execute(
        "SELECT plan, plan_until FROM users WHERE uid = %s", (event.from_uid,)
    ).fetchone()
    if row is None or row[0] == plans.FREE:
        log.info("transfer %s: nothing to move", event.id)
        return
    conn.execute(
        "UPDATE users SET plan = %s, plan_until = NULL, plan_source = NULL"
        " WHERE uid = %s",
        (plans.FREE, event.from_uid),
    )
    conn.execute(
        """
        UPDATE users
           SET plan = %s,
               plan_source = 'play',
               plan_until = GREATEST(%s, COALESCE(plan_until, %s))
         WHERE uid = %s
        """,
        (row[0], row[1], row[1], event.to_uid),
    )
    log.info("moved %s from %s to %s", row[0], event.from_uid, event.to_uid)


def _text(value) -> str | None:
    return str(value) if value else None


def _moment(millis) -> datetime | None:
    """RevenueCat sends times as milliseconds since the epoch."""
    if millis is None:
        return None
    try:
        return datetime.fromtimestamp(int(millis) / 1000, tz=UTC)
    except (TypeError, ValueError, OverflowError, OSError):
        return None
