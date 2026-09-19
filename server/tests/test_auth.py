import pytest

from tests.helpers import TEST_USER, bearer


def test_health_needs_no_sign_in(client):
    assert client.get("/health").json() == {"ok": True}


def test_me_returns_the_signed_in_user(client):
    res = client.get("/me", headers=bearer())

    assert res.status_code == 200
    assert res.json() == TEST_USER


@pytest.mark.parametrize(
    "headers",
    [{}, {"Authorization": "Basic abc"}, {"Authorization": "Bearer "}],
    ids=["no header", "wrong scheme", "empty token"],
)
def test_me_without_a_token_asks_to_sign_in(client, headers):
    res = client.get("/me", headers=headers)

    assert res.status_code == 401
    assert res.json() == {"detail": "Sign in required."}
    assert res.headers["WWW-Authenticate"] == "Bearer"


def test_me_rejects_an_invalid_token(client):
    res = client.get("/me", headers=bearer("forged-token"))

    assert res.status_code == 401
    assert res.json() == {"detail": "Invalid sign-in token."}


def test_me_tells_an_expired_session_to_sign_in_again(client):
    res = client.get("/me", headers=bearer("expired-token"))

    assert res.status_code == 401
    assert res.json() == {"detail": "Session expired. Sign in again."}


def test_me_is_503_when_google_keys_are_unreachable(client):
    res = client.get("/me", headers=bearer("certs-unreachable"))

    assert res.status_code == 503


def test_a_server_without_its_key_says_so(client):
    """A missing service account key is our problem, not the caller's."""
    res = client.get("/me", headers=bearer("server-misconfigured"))

    assert res.status_code == 503
    assert res.json() == {"detail": "Sign-in checks aren't set up on the server."}
