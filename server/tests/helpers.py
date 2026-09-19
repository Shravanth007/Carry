from firebase_admin import auth

from app.services import firebase_auth

TEST_USER = {"uid": "user-1", "email": "ada@example.com"}


def verify_test_token(token: str) -> dict:
    """Test verifier: each token string picks an outcome."""
    if token == "server-misconfigured":
        raise firebase_auth.NotConfigured("no service account key")
    if token == "expired-token":
        raise auth.ExpiredIdTokenError("expired", cause=None)
    if token == "certs-unreachable":
        raise auth.CertificateFetchError("unreachable", cause=None)
    if token != "valid-token":
        raise auth.InvalidIdTokenError("invalid")
    return TEST_USER


def bearer(token: str = "valid-token") -> dict:
    return {"Authorization": f"Bearer {token}"}
