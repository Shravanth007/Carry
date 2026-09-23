import pytest

from app.services import db, firebase_auth
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


def test_two_first_requests_do_not_fight_over_starting_firebase(monkeypatch):
    """`functools.cache` doesn't serialise its callers and FastAPI runs a `def`
    dependency in a worker thread, so two first requests could both call
    initialize_app. The loser used to get "already exists" - a ValueError that
    reads exactly like a missing key, answering 503 to a signed-in person."""
    started = object()
    monkeypatch.setattr(
        firebase_auth.firebase_admin,
        "initialize_app",
        lambda *a, **k: (_ for _ in ()).throw(ValueError("already exists")),
    )
    monkeypatch.setattr(
        firebase_auth.firebase_admin, "get_app", lambda *a, **k: started
    )
    firebase_auth.firebase_app.cache_clear()

    try:
        assert firebase_auth.firebase_app() is started
    finally:
        firebase_auth.firebase_app.cache_clear()


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

    def test_a_database_that_is_down_says_try_again(self, client, users):
        """Neon suspends an idle branch, so this is a normal Tuesday, not a bug."""
        users.fail_with = db.Unavailable("connection refused")

        res = client.get("/me", headers=bearer())

        assert res.status_code == 503
        assert res.json() == {"detail": "Carry can't reach its records. Try again."}
