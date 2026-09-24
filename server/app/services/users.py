import threading
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

import psycopg

from app.core import config
from app.services import db

# How many checks between sweeps of accounts whose entry has expired.
_SWEEP_EVERY = 500


@dataclass(frozen=True)
class CarryUser:
    """Who is calling, as this server knows them.

    `uid` always comes from a verified Firebase token, never from a request
    body, so everything keyed on it belongs to the person who signed in.
    """

    uid: str
    email: str | None
    created_at: datetime
    blocked: bool


class UserStore(Protocol):
    """Where users are kept. Tests put an in-memory one in its place."""

    def seen(self, uid: str, email: str | None) -> CarryUser:
        """Records that this account just called, creating it the first time."""
        ...


class PostgresUsers:
    """The real store. One statement: create if new, refresh if not.

    `last_seen_at` is not written on every call. Inside the rate limit one
    account can call sixty times a minute, and sixty writes a minute for one
    timestamp is a lot of write-ahead log. Between writes the row is **read**
    instead: a read costs Postgres far less, and it keeps `blocked` current, so
    cutting someone off still takes effect on their very next call.

    The email comes along on the write, and only on the write. Chasing it on
    the read path - writing whenever the token's address differs from the row -
    sounds fresher and isn't: two devices holding tokens from either side of an
    email change would each "correct" the other, writing on every call and
    leaving whichever spoke last. So `/me` can be up to
    `SEEN_WRITE_EVERY_SECONDS` behind on an email that just changed, which is a
    bounded, quiet wrongness rather than an unbounded, noisy one.

    ponytail: if an email ever has to be exact, the honest fix is the token's
    `iat` - store when the address was set and only accept a newer token - not
    a comparison that can't tell which of two tokens is newer.
    """

    def __init__(self) -> None:
        # uid -> when its last_seen_at was written, on this process's clock.
        self._written: dict[str, float] = {}
        self._lock = threading.Lock()
        self._checks = 0

    def _claim(self, uid: str, now: float | None = None) -> bool:
        """Takes the right to write this account's timestamp, or says no.

        Claimed **before** the write, not recorded after it. Recording after
        looks more honest and isn't: requests for one account arrive at the same
        moment, and if none of them has claimed yet, every one of them decides
        it is due and they all write - a stampede on a pool of five connections,
        which is exactly what the throttle exists to avoid.

        A write that then fails gives the claim back through [_release], so a
        database blip doesn't buy five minutes of not trying again either.
        """
        now = now if now is not None else time.monotonic()
        with self._lock:
            last = self._written.get(uid)
            if last is not None and now - last < config.SEEN_WRITE_EVERY_SECONDS:
                return False
            self._written[uid] = now
            self._forget_old(now)
            return True

    def _release(self, uid: str) -> None:
        """Gives back a claim whose write didn't happen."""
        with self._lock:
            self._written.pop(uid, None)

    def _forget_old(self, now: float) -> None:
        """Drops accounts whose entry has expired anyway.

        Otherwise this map keeps one entry per account for the life of the
        process - the same slow leak the rate limiter had. An entry older than
        the interval no longer decides anything, so it can go.

        Caller holds the lock.
        """
        self._checks += 1
        if self._checks % _SWEEP_EVERY:
            return
        stale = [
            uid
            for uid, when in self._written.items()
            if now - when >= config.SEEN_WRITE_EVERY_SECONDS
        ]
        for uid in stale:
            del self._written[uid]

    def seen(self, uid: str, email: str | None) -> CarryUser:
        writing = self._claim(uid)
        try:
            row = self._upsert(uid, email) if writing else self._read(uid)
            # The row can only be missing on the read path, and only if the
            # account was deleted between calls. Create it again.
            if row is None:
                row = self._upsert(uid, email)
        # Neon suspends an idle branch, and networks drop. A hiccup is a 503
        # the app can retry, not a 500 that looks like a bug in Carry.
        except psycopg.Error as e:
            if writing:
                self._release(uid)
            raise db.Unavailable(f"users.seen failed: {e}") from e
        return CarryUser(uid=row[0], email=row[1], created_at=row[2], blocked=row[3])

    def _read(self, uid: str) -> tuple | None:
        with db.connection() as conn:
            return conn.execute(
                "SELECT uid, email, created_at, blocked FROM users WHERE uid = %s",
                (uid,),
            ).fetchone()

    def _upsert(self, uid: str, email: str | None) -> tuple:
        with db.connection() as conn:
            return conn.execute(
                """
                INSERT INTO users (uid, email)
                VALUES (%s, %s)
                ON CONFLICT (uid) DO UPDATE
                    SET last_seen_at = now(),
                        -- Keep the address current, but never wipe a known one
                        -- if a token arrives without it.
                        email = COALESCE(EXCLUDED.email, users.email)
                RETURNING uid, email, created_at, blocked
                """,
                (uid, email),
            ).fetchone()


_store: UserStore = PostgresUsers()


def store() -> UserStore:
    """Dependency, so tests can swap the store without a database."""
    return _store
