import logging
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from app.services import firebase_auth

log = logging.getLogger("carry.auth")
bearer = HTTPBearer(auto_error=False)


def token_verifier() -> Callable[[str], dict]:
    """Dependency so tests can swap out token verification."""
    return firebase_auth.verify_id_token


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(401, detail, headers={"WWW-Authenticate": "Bearer"})


def current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    verify: Annotated[Callable[[str], dict], Depends(token_verifier)],
) -> dict:
    """Firebase claims of the caller. Add to any endpoint that needs sign-in."""
    if creds is None:
        raise _unauthorized("Sign in required.")
    try:
        return verify(creds.credentials)
    # Expired is a subclass of invalid, so it must come first.
    except auth.ExpiredIdTokenError:
        raise _unauthorized("Session expired. Sign in again.") from None
    except (auth.InvalidIdTokenError, ValueError):
        raise _unauthorized("Invalid sign-in token.") from None
    except auth.CertificateFetchError:
        raise HTTPException(503, "Can't verify sign-in right now. Try again.") from None
    # A server misconfiguration, not a bad token: say so instead of telling a
    # signed-in person their sign-in is invalid.
    except firebase_auth.NotConfigured as e:
        log.error("%s", e)
        raise HTTPException(503, "Sign-in checks aren't set up on the server.") from None


CurrentUser = Annotated[dict, Depends(current_user)]
