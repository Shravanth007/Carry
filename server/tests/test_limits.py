"""The limits a modified app cannot get around, because they live here."""

import threading

from fastapi import Request
from fastapi.responses import PlainTextResponse
from fastapi.testclient import TestClient
from starlette.applications import Starlette
from starlette.routing import Route

from app.core import config
from app.middleware.body_size import BodySizeLimit
from app.services import db
from app.services.rate_limit import RateLimiter, TooMany
from tests.helpers import bearer


class TestRateLimit:
    def test_an_account_gets_its_allowance(self, client, rate):
        rate.per_minute = 3

        for _ in range(3):
            assert client.get("/me", headers=bearer()).status_code == 200

    def test_and_is_told_to_slow_down_after_it(self, client, rate):
        rate.per_minute = 2
        for _ in range(2):
            client.get("/me", headers=bearer())

        res = client.get("/me", headers=bearer())

        assert res.status_code == 429
        assert "Retry-After" in res.headers
        assert int(res.headers["Retry-After"]) >= 1

    def test_one_account_cannot_use_up_another_s(self, client, rate):
        rate.per_minute = 1
        client.get("/me", headers=bearer())

        other = client.get("/me", headers=bearer("someone-else-token"))

        assert other.status_code == 200

    def test_the_window_moves_on(self):
        limiter = RateLimiter(per_minute=2)
        limiter.check("user-1", now=0)
        limiter.check("user-1", now=1)

        try:
            limiter.check("user-1", now=2)
            raise AssertionError("should have been refused")
        except TooMany:
            pass

        limiter.check("user-1", now=61)  # the first two have aged out

    def test_a_refused_request_never_reaches_the_database(self, client, rate, users):
        """The point of the limit: a flood costs a lookup, not a connection."""
        rate.per_minute = 1
        client.get("/me", headers=bearer())
        after_the_allowed_one = users.calls

        for _ in range(20):
            assert client.get("/me", headers=bearer()).status_code == 429

        assert users.calls == after_the_allowed_one

    def test_accounts_that_went_quiet_are_forgotten(self):
        """Otherwise the map keeps one entry per account for the life of the
        process, which is a leak with a very slow fuse."""
        limiter = RateLimiter(per_minute=1000)
        for i in range(600):
            limiter.check(f"user-{i}", now=0)

        # Long after their window: the next sweep should drop them.
        for _ in range(600):
            limiter.check("someone-here-now", now=1000)

        assert "user-1" not in limiter._hits  # noqa: SLF001 - that is the point
        assert "someone-here-now" in limiter._hits  # noqa: SLF001

    def test_counting_and_allowing_happen_as_one_step(self):
        """FastAPI runs this dependency in threads. Without the lock, several
        requests for one account each see room before any records its hit, and
        they all get through. Holding the lock proves `check` waits for it."""
        limiter = RateLimiter(per_minute=1)
        counted = threading.Event()
        limiter._lock.acquire()  # noqa: SLF001 - this test is about the lock
        caller = threading.Thread(target=lambda: (limiter.check("user-1"), counted.set()))
        caller.start()

        assert not counted.wait(0.1), "check counted a hit without taking the lock"

        limiter._lock.release()  # noqa: SLF001
        caller.join(timeout=1)
        assert counted.is_set()

    def test_health_is_not_rate_limited(self, client, rate):
        """It has no account to count against, and uptime checks hit it often."""
        rate.per_minute = 1

        for _ in range(5):
            assert client.get("/health").status_code == 200


class TestStartUp:
    def test_a_database_that_is_down_does_not_stop_the_server(self, monkeypatch):
        """A deploy during a Neon blip must not be a crash loop with nothing
        serving - not even /health, which is how you would find out."""
        monkeypatch.setattr(
            config, "DATABASE_URL", "postgresql://nobody@127.0.0.1:1/nothing"
        )
        monkeypatch.setattr(config, "DB_TIMEOUT_SECONDS", 1)
        db.stop()

        db.start()  # must not raise

        db.stop()


class TestBodySize:
    def test_a_huge_body_is_refused_before_it_is_read(self, client):
        res = client.post(
            "/me",
            headers={
                **bearer(),
                "Content-Length": str(config.MAX_BODY_BYTES + 1),
                "Content-Type": "application/json",
            },
            content=b"{}",
        )

        assert res.status_code == 413
        assert res.json() == {"detail": "That request is too large."}
        # Being refused is still a request worth finding in the log.
        assert "X-Request-ID" in res.headers

    def test_a_nonsense_length_is_refused(self, client):
        res = client.post(
            "/me",
            headers={**bearer(), "Content-Length": "not-a-number"},
            content=b"{}",
        )

        assert res.status_code == 400

    def test_an_ordinary_request_passes(self, client):
        assert client.get("/me", headers=bearer()).status_code == 200


class TestBodySizeWhenSomethingReadsIt:
    """The cap counts bytes, not promises.

    Carry has no endpoint that takes a body yet, and the router answers 405
    before reading one, so these go through the middleware with a small app of
    their own. That is exactly the shape the upload endpoint will have.
    """

    @staticmethod
    def _client(max_bytes: int) -> TestClient:
        async def echo(request: Request):
            body = await request.body()
            return PlainTextResponse(str(len(body)))

        app = Starlette(routes=[Route("/echo", echo, methods=["POST"])])
        app.add_middleware(BodySizeLimit, max_bytes=max_bytes)
        return TestClient(app)

    def test_a_chunked_body_over_the_cap_is_refused(self):
        """Chunked means no Content-Length, so the header check sees nothing.
        Trusting it alone makes the limit whatever the client admits to."""
        client = self._client(max_bytes=1000)

        res = client.post("/echo", content=iter([b"x" * 400] * 5))

        assert res.status_code == 413
        assert res.json() == {"detail": "That request is too large."}

    def test_a_chunked_body_under_the_cap_arrives_whole(self):
        client = self._client(max_bytes=1000)

        res = client.post("/echo", content=iter([b"x" * 100] * 5))

        assert res.status_code == 200
        assert res.text == "500"

    def test_a_declared_length_over_the_cap_never_reaches_the_route(self):
        client = self._client(max_bytes=1000)

        res = client.post("/echo", content=b"x" * 1001)

        assert res.status_code == 413
