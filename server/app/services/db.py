import logging

import psycopg
from psycopg_pool import ConnectionPool

from app.core import config

log = logging.getLogger("carry.db")

_pool: ConnectionPool | None = None


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
    """Opens the pool and makes sure the tables exist. Safe to call twice."""
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
    with _pool.connection() as conn:
        conn.execute(_SCHEMA)
    log.info("Database ready.")


def stop() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def connection() -> psycopg.Connection:
    """A connection from the pool. Use as a context manager."""
    return pool().connection()
