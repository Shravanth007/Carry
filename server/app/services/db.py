import logging

import psycopg
from psycopg_pool import ConnectionPool

from app.core import config

log = logging.getLogger("carry.db")

_pool: ConnectionPool | None = None

# Whether the tables have been created in this process. Creating them needs the
# database to answer, which it might not at start-up.
_schema_ready = False


class NotConfigured(Exception):
    """No database to talk to, so anything that needs one cannot run."""


class Unavailable(Exception):
    """There is a database, but it didn't answer. Different from NotConfigured:
    this one is worth retrying, and the caller should be told to."""


# Small on purpose: Neon's free tier has a modest connection budget, and the
# pooled host does the real multiplexing.
_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    uid           TEXT PRIMARY KEY,
    email         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Set by hand to cut someone off without deleting their account.
    blocked       BOOLEAN NOT NULL DEFAULT FALSE
);

-- Added after the table existed, so they are separate and idempotent.
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan TEXT NOT NULL DEFAULT 'free';
-- When the paid period ends. Null on free. Compared against, never trusted
-- from an event's arrival order.
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_until TIMESTAMPTZ;
-- 'play' when it was paid for, 'granted' when we gave it to someone.
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_source TEXT;

-- What an account has spent, by month. A new month is a new row: nothing has
-- to run on a schedule to reset a counter, and last month stays readable.
CREATE TABLE IF NOT EXISTS usage (
    uid                  TEXT NOT NULL,
    month                TEXT NOT NULL,          -- 'YYYY-MM', UTC
    transcribed_seconds  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (uid, month)
);

-- Every billing event we have ever applied.
--
-- The primary key IS the idempotency. Stores deliver webhooks more than once,
-- and an INSERT that loses to a duplicate tells us so without a
-- check-then-write race to get wrong. It is also the audit trail: when someone
-- says they paid, this is what we read.
CREATE TABLE IF NOT EXISTS billing_events (
    event_id     TEXT PRIMARY KEY,
    uid          TEXT,
    kind         TEXT NOT NULL,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Why an event we accepted changed nothing, when that needs a person.
--
-- Acknowledging is the right answer to the store - it would redeliver the
-- same payload and get the same result - but it must not be silent. This is
-- the queue of events to look at by hand:
--
--   SELECT event_id, kind, received_at, problem
--     FROM billing_events WHERE problem IS NOT NULL ORDER BY received_at;
--
-- ponytail: a query and a fix by hand. An admin screen is the upgrade, and it
-- earns its keep when this list stops being empty - not before, because it
-- would be a second way to change a plan and a second way to get it wrong.
ALTER TABLE billing_events ADD COLUMN IF NOT EXISTS problem TEXT;
"""


def pool() -> ConnectionPool:
    """The connection pool, or NotConfigured when there is no database."""
    if _pool is None:
        raise NotConfigured(
            "No DATABASE_URL. Set it in server/.env to the Neon connection "
            "string. See app/docs/security.md."
        )
    return _pool


def start() -> None:
    """Opens the pool and makes sure the tables exist. Safe to call twice.

    A database that doesn't answer is not a reason to refuse to start. Neon
    suspends an idle branch, and a blip during a deploy would otherwise be a
    crash loop with nothing serving — not even `/health`, which is how you'd
    find out. The pool reconnects on its own, so the tables are created on the
    first request that gets through, and until then requests answer 503.
    """
    global _pool
    if _pool is not None:
        return
    if not config.DATABASE_URL:
        log.warning(
            "No DATABASE_URL: anything that needs the database will answer 503."
        )
        return
    _pool = ConnectionPool(
        config.DATABASE_URL,
        min_size=1,
        max_size=config.DB_MAX_CONNECTIONS,
        open=True,
        timeout=config.DB_TIMEOUT_SECONDS,
    )
    _ensure_schema()


def _ensure_schema() -> None:
    """Creates the tables if they aren't there. Does nothing once it has."""
    global _schema_ready
    if _schema_ready or _pool is None:
        return
    try:
        with _pool.connection() as conn:
            conn.execute(_SCHEMA)
        _schema_ready = True
        log.info("Database ready.")
    # Deliberately broad: a pool timeout, a DNS failure and a refused
    # connection are all "not yet", and none of them may stop the process.
    except Exception as e:
        log.error("Database not ready yet, will try again on the next call: %s", e)


def stop() -> None:
    global _pool, _schema_ready
    if _pool is not None:
        _pool.close()
        _pool = None
    _schema_ready = False


def connection() -> psycopg.Connection:
    """A connection from the pool. Use as a context manager.

    Creates the tables first if start-up couldn't, so a database that was down
    when the server booted needs nothing but the next request.
    """
    handle = pool()
    _ensure_schema()
    return handle.connection()
