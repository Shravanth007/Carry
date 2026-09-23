import pytest

from app.services import db
from tests.helpers import TEST_EMAIL, TEST_UID, bearer


def test_health_needs_no_sign_in(client):
    assert client.get("/health").json() == {"ok": True}


def test_me_returns_the_signed_in_user(client):
    res = client.get("/me", headers=bearer())

    assert res.status_code == 200
    body = res.json()
    assert body["uid"] == TEST_UID
    assert body["email"] == TEST_EMAIL
    assert body["since"]


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
    assert client.get("/me", headers=bearer("certs-unreachable")).status_code == 503


def test_a_server_without_its_key_says_so(client):
    """A missing service account key is our problem, not the caller's."""
    res = client.get("/me", headers=bearer("server-misconfigured"))

    assert res.status_code == 503
    assert res.json() == {"detail": "Sign-in checks aren't set up on the server."}


def test_a_token_with_no_uid_is_refused(client):
    """Every real Firebase token carries one. A token without it isn't ours."""
    res = client.get("/me", headers=bearer("no-uid-token"))

    assert res.status_code == 401


class TestTheAccountRecord:
    def test_first_call_creates_the_account(self, client, users):
        assert users.rows == {}

        client.get("/me", headers=bearer())

        assert users.rows[TEST_UID].email == TEST_EMAIL

    def test_later_calls_keep_the_same_account(self, client, users):
        first = client.get("/me", headers=bearer()).json()["since"]

        second = client.get("/me", headers=bearer()).json()["since"]

        assert first == second, "joined-on date does not move"
        assert len(users.rows) == 1

    def test_each_token_gets_its_own_account(self, client, users):
        client.get("/me", headers=bearer())
        client.get("/me", headers=bearer("someone-else-token"))

        assert set(users.rows) == {TEST_UID, "user-2"}

    def test_a_blocked_account_is_turned_away(self, client, users):
        users.blocked.add(TEST_UID)

        res = client.get("/me", headers=bearer())

        assert res.status_code == 403
        assert res.json() == {"detail": "This account can't use Carry."}

    def test_no_database_is_a_server_problem(self, client, users):
        users.fail_with = db.NotConfigured("no DATABASE_URL")

        res = client.get("/me", headers=bearer())

        assert res.status_code == 503
        assert res.json() == {"detail": "Carry isn't set up to store accounts yet."}
