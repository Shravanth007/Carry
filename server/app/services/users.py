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
    account can call sixty times a minute, and sixty writes a minute per person
    is a lot of write-ahead log for one timestamp nobody reads that precisely.
    Between writes the row is **read** instead: a read costs Postgres far less,
    and it keeps `blocked` current, so cutting someone off still takes effect on
    their next call rather than minutes later.
    """

    def __init__(self) -> None:
        # uid -> when its last_seen_at was written, on this process's clock.
        self._written: dict[str, float] = {}
        self._lock = threading.Lock()
        self._checks = 0

    def _due(self, uid: str, now: float | None = None) -> bool:
        """Whether this account's timestamp is old enough to write again."""
        now = now if now is not None else time.monotonic()
        with self._lock:
            last = self._written.get(uid)
            return last is None or now - last >= config.SEEN_WRITE_EVERY_SECONDS

    def _wrote(self, uid: str, now: float | None = None) -> None:
        """Remembers a write that actually happened.

        Recorded after the write, not before: a write that failed in a database
        blip must not buy five minutes of not trying again.
        """
        now = now if now is not None else time.monotonic()
        with self._lock:
            self._written[uid] = now
            self._forget_old(now)

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
        try:
            row = None if self._due(uid) else self._read(uid)
            # Three ways to end up writing after all: the interval passed, the
            # row is gone (deleted between calls), or the token carries a newer
            # email than the row - /me must not answer with an old address.
            if row is None or (email is not None and row[1] != email):
                row = self._upsert(uid, email)
                self._wrote(uid)
        # Neon suspends an idle branch, and networks drop. A hiccup is a 503
        # the app can retry, not a 500 that looks like a bug in Carry.
        except psycopg.Error as e:
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
