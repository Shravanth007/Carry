from datetime import UTC, datetime

from firebase_admin import auth

from app.services import firebase_auth
from app.services.users import CarryUser

TEST_UID = "user-1"
TEST_EMAIL = "ada@example.com"
TEST_USER = {"uid": TEST_UID, "email": TEST_EMAIL}


def verify_test_token(token: str) -> dict:
    """Test verifier: each token string picks an outcome."""
    if token == "server-misconfigured":
        raise firebase_auth.NotConfigured("no service account key")
    if token == "expired-token":
        raise auth.ExpiredIdTokenError("expired", cause=None)
    if token == "certs-unreachable":
        raise auth.CertificateFetchError("unreachable", cause=None)
    if token == "no-uid-token":
        return {"email": TEST_EMAIL}
    if token == "someone-else-token":
        return {"uid": "user-2", "email": "grace@example.com"}
    if token != "valid-token":
        raise auth.InvalidIdTokenError("invalid")
    return dict(TEST_USER)


class TestUsers:
    """Accounts in memory, so tests never need a database."""

    def __init__(self) -> None:
        self.rows: dict[str, CarryUser] = {}
        self.blocked: set[str] = set()
        self.fail_with: Exception | None = None
        self.calls = 0

    def seen(self, uid: str, email: str | None) -> CarryUser:
        self.calls += 1
        if self.fail_with is not None:
            raise self.fail_with
        existing = self.rows.get(uid)
        user = CarryUser(
            uid=uid,
            email=email or (existing.email if existing else None),
            created_at=existing.created_at if existing else datetime.now(UTC),
            blocked=uid in self.blocked,
        )
        self.rows[uid] = user
        return user


def bearer(token: str = "valid-token") -> dict:
    return {"Authorization": f"Bearer {token}"}
