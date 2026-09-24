"""What keeps the server up when someone points a loop at it.

These are the limits that don't need to know who you are. Every other limit
Carry has is per account, so none of them apply until a token has verified -
which left a script with no account unlimited.
"""

import anyio
import httpx
import pytest
from fastapi import FastAPI

from app.core import config
from app.middleware.load import LoadShedder, client_address
from app.services import firebase_auth
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
    """`X-Forwarded-For` is a header, so it is only as trustworthy as whatever
    set it. Believing it without a proxy in front would let one script claim a
    thousand addresses and skip the limit entirely."""

    def test_the_socket_address_is_used_by_default(self, monkeypatch):
        monkeypatch.setattr(config, "TRUST_PROXY_HEADER", False)
        request = _FakeRequest(host="9.9.9.9", forwarded="1.1.1.1, 2.2.2.2")

        assert client_address(request) == "9.9.9.9"

    def test_the_proxy_header_is_used_when_it_can_be_trusted(self, monkeypatch):
        monkeypatch.setattr(config, "TRUST_PROXY_HEADER", True)
        request = _FakeRequest(host="9.9.9.9", forwarded="1.1.1.1, 2.2.2.2")

        # The last hop: the one our own proxy wrote. Earlier entries came from
        # the client and can say anything.
        assert client_address(request) == "2.2.2.2"

    def test_a_request_with_no_address_still_counts_as_something(self, monkeypatch):
        monkeypatch.setattr(config, "TRUST_PROXY_HEADER", True)
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

    def test_the_first_call_writes(self):
        store = PostgresUsers()

        assert store._due("ada", now=0) is True  # noqa: SLF001 - the point

    def test_a_call_straight_after_reads_instead(self):
        store = PostgresUsers()
        store._due("ada", now=0)  # noqa: SLF001

        assert store._due("ada", now=30) is False  # noqa: SLF001

    def test_and_writes_again_once_the_interval_has_passed(self):
        store = PostgresUsers()
        store._due("ada", now=0)  # noqa: SLF001
        later = config.SEEN_WRITE_EVERY_SECONDS + 1

        assert store._due("ada", now=later) is True  # noqa: SLF001

    def test_accounts_are_counted_apart(self):
        store = PostgresUsers()
        store._due("ada", now=0)  # noqa: SLF001

        assert store._due("grace", now=0) is True  # noqa: SLF001


def test_the_limiter_classes_are_the_same_one(fresh_ip_limit):
    """Addresses and accounts are counted by the same sliding window, with
    different allowances, so there is one piece of counting to get right."""
    assert isinstance(fresh_ip_limit, RateLimiter)
