from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

from app.services import db


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
    """The real store. One statement: create if new, refresh if not."""

    def seen(self, uid: str, email: str | None) -> CarryUser:
        with db.connection() as conn:
            row = conn.execute(
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
        return CarryUser(uid=row[0], email=row[1], created_at=row[2], blocked=row[3])


_store: UserStore = PostgresUsers()


def store() -> UserStore:
    """Dependency, so tests can swap the store without a database."""
    return _store
