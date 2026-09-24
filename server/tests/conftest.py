import pytest
from fastapi.testclient import TestClient

from app.dependencies.auth import token_verifier
from app.main import app
from app.services import rate_limit as rate_limit_module
from app.services.rate_limit import RateLimiter, limiter
from app.services.users import store
from tests.helpers import TestUsers, verify_test_token


@pytest.fixture
def users() -> TestUsers:
    """The accounts this test's server knows about."""
    return TestUsers()


@pytest.fixture
def rate() -> RateLimiter:
    """A fresh limiter, so one test's calls never count against another's."""
    return RateLimiter(per_minute=1000)


@pytest.fixture(autouse=True)
def fresh_ip_limit():
    """A per-address limiter of this test's own.

    Middleware can't take a dependency, so it reads the module's limiter, and
    every test calls from the same address. Sharing one would mean a long test
    run refusing its own requests.
    """
    was = rate_limit_module._ip_limiter  # noqa: SLF001 - swapping the singleton
    rate_limit_module._ip_limiter = RateLimiter(per_minute=1000)
    yield rate_limit_module._ip_limiter
    rate_limit_module._ip_limiter = was


@pytest.fixture
def client(users: TestUsers, rate: RateLimiter):
    """API client with test sign-in, test accounts and a fresh rate limit."""
    app.dependency_overrides[token_verifier] = lambda: verify_test_token
    app.dependency_overrides[store] = lambda: users
    app.dependency_overrides[limiter] = lambda: rate
    yield TestClient(app)
    app.dependency_overrides.clear()
