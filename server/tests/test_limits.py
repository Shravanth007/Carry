"""The limits a modified app cannot get around, because they live here."""

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
