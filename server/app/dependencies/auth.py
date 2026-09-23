import logging
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from app.services import db, firebase_auth
from app.services.rate_limit import RateLimiter, TooMany, limiter
from app.services.users import CarryUser, UserStore, store

log = logging.getLogger("carry.auth")
bearer = HTTPBearer(auto_error=False)


def token_verifier() -> Callable[[str], dict]:
    """Dependency so tests can swap out token verification."""
    return firebase_auth.verify_id_token


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(401, detail, headers={"WWW-Authenticate": "Bearer"})


def _claims(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    verify: Annotated[Callable[[str], dict], Depends(token_verifier)],
) -> dict:
    """What the verified Firebase token says. Nothing here is client input."""
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


def current_user(
    claims: Annotated[dict, Depends(_claims)],
    users: Annotated[UserStore, Depends(store)],
    rate: Annotated[RateLimiter, Depends(limiter)],
) -> CarryUser:
    """The signed-in caller, allowed to make this request.

    Runs on every protected endpoint, in this order:
      1. the token is real, so the uid can be trusted,
      2. the account exists here (created on first sight),
      3. it isn't blocked,
      4. it is within its rate limit.

    None of these can be skipped by a modified app: it is all server side.
    """
    uid = claims.get("uid") or claims.get("user_id")
    if not uid:
        # A verified token always carries one; a token that doesn't is not ours.
        raise _unauthorized("Invalid sign-in token.")

    try:
        user = users.seen(uid, claims.get("email"))
    except db.NotConfigured as e:
        log.error("%s", e)
        raise HTTPException(503, "Carry isn't set up to store accounts yet.") from None

    if user.blocked:
        log.warning("blocked account tried to call: %s", uid)
        raise HTTPException(403, "This account can't use Carry.")

    try:
        rate.check(uid)
    except TooMany as e:
        raise HTTPException(
            429,
            "Too many requests. Slow down and try again shortly.",
            headers={"Retry-After": str(e.retry_after)},
        ) from None

    return user


CurrentUser = Annotated[CarryUser, Depends(current_user)]
