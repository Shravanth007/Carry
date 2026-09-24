"""What keeps the server up when someone points a loop at it.

These are the limits that don't need to know who you are. Every other limit
Carry has is per account, so none of them apply until a token has verified -
which left a script with no account unlimited.
"""

import logging
from datetime import UTC, datetime

import anyio
import httpx
import psycopg
import pytest
from fastapi import FastAPI

from app.core import config
from app.middleware import load
from app.middleware.load import LoadShedder, client_address
from app.services import db, firebase_auth
from app.services.rate_limit import RateLimiter
from app.services.users import PostgresUsers
from tests.helpers import bearer


class TestPerAddressLimit:
    def test_an_address_gets_an_allowance(self, client, fresh_ip_limit):
        fresh_ip_limit.per_minute = 3

        for _ in range(3):
            assert client.get("/health").status_code == 200

    def test_and_is_told_to_slow_down_after_it(self, client, fresh_ip_limit):
        fresh_ip_limit.per_minute = 2
        for _ in range(2):
            client.get("/health")

        res = client.get("/health")

        assert res.status_code == 429
        assert int(res.headers["Retry-After"]) >= 1

    def test_it_applies_to_health_too(self, client, fresh_ip_limit):
        """The per-account limit skips /health because it has no account. This
        one is what stops /health being a free way to load the server."""
        fresh_ip_limit.per_minute = 1
        client.get("/health")

        assert client.get("/health").status_code == 429

    def test_it_applies_before_a_token_is_checked(self, client, fresh_ip_limit):
        """The point of it: junk tokens are counted, even though they never
        reach the per-account limiter."""
        fresh_ip_limit.per_minute = 2
        for _ in range(2):
            assert client.get("/me", headers=bearer("forged-token")).status_code == 401

        res = client.get("/me", headers=bearer("forged-token"))

        assert res.status_code == 429


class TestWhichAddress:
    """The connection's address, and nothing a caller can write.

    `X-Forwarded-For` is deliberately not read here. A caller who can reach the
    server directly would rotate the last hop and get a fresh allowance every
    request - a limit that looks like it works and doesn't. Behind a proxy,
    uvicorn's `--forwarded-allow-ips` rewrites the client address for that peer
    only, so this reads the right thing without us implementing proxy trust.
    """

    def test_the_connection_address_is_used(self):
        request = _FakeRequest(host="9.9.9.9", forwarded="1.1.1.1, 2.2.2.2")

        assert client_address(request) == "9.9.9.9"

    def test_a_forwarded_header_cannot_change_the_key(self):
        one = _FakeRequest(host="9.9.9.9", forwarded="a")
        two = _FakeRequest(host="9.9.9.9", forwarded="b")

        assert client_address(one) == client_address(two)

    def test_a_request_with_no_address_still_counts_as_something(self):
        request = _FakeRequest(host=None, forwarded=None)

        assert client_address(request) == "unknown"


class _FakeRequest:
    def __init__(self, host: str | None, forwarded: str | None):
        self.headers = {"X-Forwarded-For": forwarded} if forwarded else {}
        self.client = _FakeClient(host) if host else None
        self.url = httpx.URL("http://test/me")


class _FakeClient:
    def __init__(self, host: str):
        self.host = host


class TestLoadShedder:
    """Refusing beats queueing: a queue holds memory and workers until nothing
    finishes."""

    def test_a_request_too_many_is_refused_at_once(self):
        held = anyio.Event()
        arrived = anyio.Event()

        app = FastAPI()

        @app.get("/slow")
        async def slow():
            arrived.set()
            await held.wait()
            return {"ok": True}

        app.add_middleware(LoadShedder, most=1)

        async def scenario():
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(
                transport=transport, base_url="http://test"
            ) as web:
                second: list[int] = []

                async def first():
                    await web.get("/slow")

                async def rest():
                    await arrived.wait()  # one is in flight and staying there
                    second.append((await web.get("/slow")).status_code)
                    held.set()

                # A deadline, so a shedder that isn't shedding fails the test
                # instead of hanging it: the held request would never be let go.
                with anyio.fail_after(5):
                    async with anyio.create_task_group() as work:
                        work.start_soon(first)
                        work.start_soon(rest)
                return second[0]

        assert anyio.run(scenario) == 503

    def test_and_serves_again_once_there_is_room(self):
        app = FastAPI()

        @app.get("/quick")
        async def quick():
            return {"ok": True}

        app.add_middleware(LoadShedder, most=1)

        async def scenario():
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(
                transport=transport, base_url="http://test"
            ) as web:
                one = await web.get("/quick")
                two = await web.get("/quick")
                return one.status_code, two.status_code

        assert anyio.run(scenario) == (200, 200)


class TestCheapRefusals:
    """A token that cannot be real must not cost a signature check."""

    @pytest.mark.parametrize(
        "token",
        ["", "nope", "a.b", "a.b.c", "x" * 5000, "header..signature"],
    )
    def test_a_token_that_is_not_a_jwt_never_reaches_firebase(
        self, token, monkeypatch
    ):
        def must_not_be_called():
            raise AssertionError("checked a signature for a token that can't be one")

        monkeypatch.setattr(firebase_auth, "firebase_app", must_not_be_called)

        with pytest.raises(ValueError):
            firebase_auth.verify_id_token(token)

    def test_something_shaped_like_a_token_does_reach_firebase(self, monkeypatch):
        """The cheap check must not become a filter that refuses real tokens."""
        reached = []
        monkeypatch.setattr(firebase_auth, "firebase_app", lambda: reached.append(1))
        monkeypatch.setattr(
            firebase_auth.auth, "verify_id_token", lambda token, app: {"uid": "ada"}
        )

        claims = firebase_auth.verify_id_token(f"{'h' * 20}.{'p' * 20}.{'s' * 20}")

        assert claims == {"uid": "ada"}
        assert reached == [1]


class TestWriteThrottle:
    """Sixty calls a minute is inside the per-account limit; sixty writes a
    minute for one timestamp is not worth the write-ahead log."""

    def test_the_first_call_claims_the_write(self):
        store = PostgresUsers()

        assert store._claim("ada", now=0) == 0  # noqa: SLF001 - the point

    def test_a_call_straight_after_reads_instead(self):
        store = PostgresUsers()
        store._claim("ada", now=0)  # noqa: SLF001

        assert store._claim("ada", now=30) is None  # noqa: SLF001

    def test_requests_at_the_same_moment_do_not_all_write(self):
        """The reason the claim is taken before the write, not recorded after
        it: several requests for one account arrive together, and if none has
        claimed yet they all decide they are due - a stampede on a pool of
        five connections."""
        store = PostgresUsers()

        claims = [store._claim("ada", now=0) for _ in range(20)]  # noqa: SLF001

        assert len([c for c in claims if c is not None]) == 1

    def test_and_claims_again_once_the_interval_has_passed(self):
        store = PostgresUsers()
        store._claim("ada", now=0)  # noqa: SLF001
        later = config.SEEN_WRITE_EVERY_SECONDS + 1

        assert store._claim("ada", now=later) == later  # noqa: SLF001

    def test_a_claim_given_back_lets_the_next_call_try(self):
        """A write that failed in a database blip must not buy five minutes of
        not trying again."""
        store = PostgresUsers()
        claimed = store._claim("ada", now=0)  # noqa: SLF001

        store._release("ada", claimed)  # noqa: SLF001

        assert store._claim("ada", now=1) == 1  # noqa: SLF001

    def test_a_late_failure_cannot_give_back_someone_else_s_claim(self):
        """A write slow enough to outlive the interval can fail after another
        request has taken the slot. Releasing then would undo a throttle the
        failure had nothing to do with."""
        store = PostgresUsers()
        slow = store._claim("ada", now=0)  # noqa: SLF001
        later = config.SEEN_WRITE_EVERY_SECONDS + 1
        store._claim("ada", now=later)  # noqa: SLF001 - the next one takes it

        store._release("ada", slow)  # noqa: SLF001 - the slow write finally fails

        assert store._claim("ada", now=later + 1) is None  # noqa: SLF001

    def test_accounts_are_counted_apart(self):
        store = PostgresUsers()
        store._claim("ada", now=0)  # noqa: SLF001

        assert store._claim("grace", now=0) is not None  # noqa: SLF001


class _FakeCursor:
    def __init__(self, row):
        self.row = row

    def fetchone(self):
        return self.row


class _FakeConnection:
    """Stands in for a pooled Postgres connection, recording the SQL it was
    given so a test can see which path ran."""

    def __init__(self, answers: list, statements: list[str]):
        self.answers = answers
        self.statements = statements

    def execute(self, sql, params=None):
        self.statements.append(" ".join(sql.split())[:40])
        if not self.answers:
            raise AssertionError("more queries than the test set up")
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return _FakeCursor(answer)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def _store_talking_to(monkeypatch, answers: list) -> tuple[PostgresUsers, list[str]]:
    """A store whose database says exactly what the test wants."""
    statements: list[str] = []
    monkeypatch.setattr(
        db, "connection", lambda: _FakeConnection(answers, statements)
    )
    return PostgresUsers(), statements


ROW = ("ada", "ada@example.com", datetime(2026, 1, 1, tzinfo=UTC), False, "free", None)


class TestSeenAgainstTheDatabase:
    """The read path, its fallback and its failures - the tests above only cover
    the decision, and the route tests swap the whole store out."""

    def test_the_first_call_writes_and_returns_the_row(self, monkeypatch):
        store, statements = _store_talking_to(monkeypatch, [ROW])

        user = store.seen("ada", "ada@example.com")

        assert user.uid == "ada"
        assert statements[0].startswith("INSERT INTO users")

    def test_the_next_call_reads_instead_of_writing(self, monkeypatch):
        store, statements = _store_talking_to(monkeypatch, [ROW, ROW])
        store.seen("ada", "ada@example.com")

        store.seen("ada", "ada@example.com")

        assert statements[1].startswith("SELECT")

    def test_a_blocked_account_is_seen_on_the_read_path(self, monkeypatch):
        """Blocking has to take effect on the next call, not in five minutes."""
        blocked = ("ada", "ada@example.com", ROW[2], True, "free", None)
        store, _ = _store_talking_to(monkeypatch, [ROW, blocked])
        store.seen("ada", "ada@example.com")

        assert store.seen("ada", "ada@example.com").blocked is True

    def test_an_email_change_waits_for_the_next_write(self, monkeypatch):
        """Deliberate: chasing the token's email on the read path means two
        devices holding tokens from either side of a change each "correct" the
        other, writing on every call. /me is instead up to one interval behind,
        which is quieter and bounded."""
        store, statements = _store_talking_to(monkeypatch, [ROW, ROW])
        store.seen("ada", "ada@example.com")

        user = store.seen("ada", "new@example.com")

        assert user.email == "ada@example.com"
        assert statements[1].startswith("SELECT")

    def test_and_the_next_write_takes_it(self, monkeypatch):
        renamed = ("ada", "new@example.com", ROW[2], False, "free", None)
        store, statements = _store_talking_to(monkeypatch, [ROW, renamed])
        store.seen("ada", "ada@example.com")
        store._written.clear()  # noqa: SLF001 - stands in for the interval passing

        user = store.seen("ada", "new@example.com")

        assert user.email == "new@example.com"
        assert statements[1].startswith("INSERT INTO users")

    def test_a_row_that_vanished_is_created_again(self, monkeypatch):
        store, statements = _store_talking_to(monkeypatch, [ROW, None, ROW])
        store.seen("ada", "ada@example.com")

        user = store.seen("ada", "ada@example.com")

        assert user.uid == "ada"
        assert statements[2].startswith("INSERT INTO users")

    def test_a_database_failure_becomes_unavailable(self, monkeypatch):
        store, _ = _store_talking_to(
            monkeypatch, [psycopg.OperationalError("connection refused")]
        )

        with pytest.raises(db.Unavailable):
            store.seen("ada", "ada@example.com")

    def test_and_a_failed_write_is_retried_on_the_next_call(self, monkeypatch):
        store, statements = _store_talking_to(
            monkeypatch, [psycopg.OperationalError("blip"), ROW]
        )
        with pytest.raises(db.Unavailable):
            store.seen("ada", "ada@example.com")

        store.seen("ada", "ada@example.com")

        # Both attempts wrote: the first one failed, so it bought nothing.
        assert [s.split()[0] for s in statements] == ["INSERT", "INSERT"]


class TestRefusalLogs:
    """A flood must not become a log flood: that is work added exactly when the
    point is to refuse work cheaply."""

    def test_each_address_gets_its_own_line(self, caplog, monkeypatch):
        """Sampling by kind alone would name whichever address triggered the
        next line and lose the others - and the address is what an operator
        blocks."""
        monkeypatch.setattr(load, "_last_logged", {})
        monkeypatch.setattr(load, "_suppressed", {})

        with caplog.at_level(logging.WARNING, logger="carry.load"):
            for address in ("1.1.1.1", "2.2.2.2", "3.3.3.3"):
                for _ in range(10):
                    load._log_sometimes(  # noqa: SLF001
                        f"rate:{address}", "rate limited %s", address
                    )

        named = {record.message.split()[-1] for record in caplog.records}
        assert named == {"1.1.1.1", "2.2.2.2", "3.3.3.3"}

    def test_repeated_refusals_are_summarised(self, caplog, monkeypatch):
        monkeypatch.setattr(load, "_last_logged", {})
        monkeypatch.setattr(load, "_suppressed", {})

        with caplog.at_level(logging.WARNING, logger="carry.load"):
            for _ in range(50):
                load._log_sometimes("rate", "refused %s", "1.2.3.4")  # noqa: SLF001

        # One line for fifty refusals, not fifty lines.
        assert len(caplog.records) == 1

    def test_and_the_next_line_says_how_many_were_missed(self, caplog, monkeypatch):
        monkeypatch.setattr(load, "_last_logged", {})
        monkeypatch.setattr(load, "_suppressed", {})
        clock = [0.0]
        monkeypatch.setattr(load.time, "monotonic", lambda: clock[0])

        with caplog.at_level(logging.WARNING, logger="carry.load"):
            for _ in range(10):
                load._log_sometimes("rate", "refused %s", "1.2.3.4")  # noqa: SLF001
            clock[0] = load._LOG_EVERY + 1  # noqa: SLF001
            load._log_sometimes("rate", "refused %s", "1.2.3.4")  # noqa: SLF001

        assert "and 9 more" in caplog.records[-1].message
