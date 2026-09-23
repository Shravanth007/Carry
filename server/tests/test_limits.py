"""The limits a modified app cannot get around, because they live here."""

import threading

from app.core import config
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

    def test_a_nonsense_length_is_refused(self, client):
        res = client.post(
            "/me",
            headers={**bearer(), "Content-Length": "not-a-number"},
            content=b"{}",
        )

        assert res.status_code == 400

    def test_an_ordinary_request_passes(self, client):
        assert client.get("/me", headers=bearer()).status_code == 200
