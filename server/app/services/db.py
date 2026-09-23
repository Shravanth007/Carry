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
