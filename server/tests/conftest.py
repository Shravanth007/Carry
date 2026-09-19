import pytest
from fastapi.testclient import TestClient

from app.dependencies.auth import token_verifier
from app.main import app
from tests.helpers import verify_test_token


@pytest.fixture
def client():
    """API client where sign-in tokens are checked by the test verifier."""
    app.dependency_overrides[token_verifier] = lambda: verify_test_token
    yield TestClient(app)
    app.dependency_overrides.clear()
