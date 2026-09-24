"""What an account has spent this month, and whether it may spend more.

Counted in seconds of transcribed audio, because that is what Groq bills for.
Kept per month in its own row, so nothing has to run on a schedule to reset a
counter and last month stays readable.
"""

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

import psycopg

from app.services import db, plans
from app.services.users import CarryUser

log = logging.getLogger("carry.usage")


class OverQuota(Exception):
    """This account has spent its allowance for the month."""

    def __init__(self, used: int, allowed: int):
        super().__init__(f"{used}s used of {allowed}s")
        self.used = used
        self.allowed = allowed


@dataclass(frozen=True)
class Spent:
    used_seconds: int
    allowed_seconds: int

    @property
    def left_seconds(self) -> int:
        return max(0, self.allowed_seconds - self.used_seconds)


def month_of(when: datetime | None = None) -> str:
    """The month a moment belongs to, in UTC.

    UTC rather than anyone's local time: a month that starts at a different
    moment for each person is a month that can be started twice by flying.
    """
    when = when or datetime.now(UTC)
    return when.astimezone(UTC).strftime("%Y-%m")


class UsageStore(Protocol):
    """Where usage is kept. Tests put an in-memory one in its place."""

    def used(self, uid: str, month: str) -> int:
        """Seconds transcribed by this account in this month."""
        ...

    def record(self, uid: str, month: str, seconds: int) -> None:
        """Adds to that."""
        ...


class PostgresUsage:
    def used(self, uid: str, month: str) -> int:
        try:
            with db.connection() as conn:
                row = conn.execute(
                    "SELECT transcribed_seconds FROM usage"
                    " WHERE uid = %s AND month = %s",
                    (uid, month),
                ).fetchone()
        except psycopg.Error as e:
            raise db.Unavailable(f"usage lookup failed: {e}") from e
        return row[0] if row else 0

    def record(self, uid: str, month: str, seconds: int) -> None:
        try:
            with db.connection() as conn:
                conn.execute(
                    """
                    INSERT INTO usage (uid, month, transcribed_seconds)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (uid, month) DO UPDATE
                        SET transcribed_seconds = usage.transcribed_seconds
                                                + EXCLUDED.transcribed_seconds
                    """,
                    (uid, month, seconds),
                )
        except psycopg.Error as e:
            raise db.Unavailable(f"usage.record failed: {e}") from e


_usage: UsageStore = PostgresUsage()


def store() -> UsageStore:
    """Dependency, so tests can count without a database."""
    return _usage


def spent(store: UsageStore, user: CarryUser, when: datetime | None = None) -> Spent:
    """How much of this month's allowance is gone."""
    return Spent(
        used_seconds=store.used(user.uid, month_of(when)),
        allowed_seconds=plans.allowance(user.plan).transcription_seconds,
    )


def check(
    store: UsageStore,
    user: CarryUser,
    seconds: int,
    when: datetime | None = None,
) -> None:
    """Raises OverQuota unless this account can afford [seconds] more.

    Called **before** the money is spent — before a signed upload URL exists,
    and before Groq is asked to transcribe anything. Afterwards is too late: a
    signed URL is storage already spent, and a transcription already billed.

    ponytail: no caller yet. The upload and transcription endpoints are the
    callers, and this is deliberately ready before them, because the version of
    this written in a hurry is the one that checks the quota after the spending.
    """
    now = spent(store, user, when)
    if now.used_seconds + seconds > now.allowed_seconds:
        raise OverQuota(used=now.used_seconds, allowed=now.allowed_seconds)


def record(
    store: UsageStore,
    uid: str,
    seconds: int,
    when: datetime | None = None,
) -> None:
    """Adds to what this account has spent this month.

    Recorded after the work succeeded. Charging someone for a transcription
    that failed would be the worst kind of wrong: they pay and get nothing.
    """
    if seconds <= 0:
        return
    store.record(uid, month_of(when), seconds)
