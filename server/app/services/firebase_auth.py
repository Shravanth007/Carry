import threading
from functools import cache

import firebase_admin
from firebase_admin import auth
from google.auth.exceptions import DefaultCredentialsError


class NotConfigured(Exception):
    """No usable service account key, so no token can be checked."""


_starting = threading.Lock()


@cache
def firebase_app() -> firebase_admin.App:
    """The Firebase app, started once.

    Credentials and project ID come from the service account file named by
    GOOGLE_APPLICATION_CREDENTIALS. Created on first use, not at import.

    Locked, and it takes an existing app if there is one. `functools.cache`
    doesn't serialise its callers, and FastAPI runs a `def` dependency in a
    worker thread: two first requests could both call `initialize_app`, and the
    loser gets "the default Firebase app already exists" — a ValueError that
    reads exactly like a missing key and would answer 503 to a signed-in
    person.
    """
    with _starting:
        try:
            return firebase_admin.get_app()
        except ValueError:
            pass  # Not started yet, which is the normal case.
        try:
            return firebase_admin.initialize_app()
        except (DefaultCredentialsError, OSError, ValueError) as e:
            raise NotConfigured(
                "No Firebase service account key. Set "
                "GOOGLE_APPLICATION_CREDENTIALS in server/.env to the key "
                "file. See app/docs/auth.md."
            ) from e


# A Firebase ID token is a JWT: three dot-separated parts, around a thousand
# characters. Anything else cannot possibly verify.
_SHORTEST = 40
_LONGEST = 4096


def _could_be_a_token(token: str) -> bool:
    if not _SHORTEST <= len(token) <= _LONGEST:
        return False
    parts = token.split(".")
    return len(parts) == 3 and all(parts)


def verify_id_token(token: str) -> dict:
    """Claims (uid, email, ...) of a valid Firebase ID token.

    Raises firebase_admin.auth errors (invalid, expired, certificate fetch)
    or ValueError for a token that isn't one.

    Shape is checked first, which costs a string split. Verifying a signature
    costs public-key crypto, so a flood of junk tokens would otherwise be a way
    to spend the server's CPU without having an account at all.
    """
    if not _could_be_a_token(token):
        raise ValueError("not a JWT")
    return auth.verify_id_token(token, app=firebase_app())
