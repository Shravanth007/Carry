from functools import cache

import firebase_admin
from firebase_admin import auth
from google.auth.exceptions import DefaultCredentialsError


class NotConfigured(Exception):
    """No usable service account key, so no token can be checked."""


@cache
def firebase_app() -> firebase_admin.App:
    # Credentials and project ID come from the service account file named by
    # GOOGLE_APPLICATION_CREDENTIALS. Created on first use, not at import.
    try:
        return firebase_admin.initialize_app()
    except (DefaultCredentialsError, OSError, ValueError) as e:
        raise NotConfigured(
            "No Firebase service account key. Set GOOGLE_APPLICATION_CREDENTIALS "
            "in server/.env to the key file. See app/docs/auth.md."
        ) from e


def verify_id_token(token: str) -> dict:
    """Claims (uid, email, ...) of a valid Firebase ID token.

    Raises firebase_admin.auth errors (invalid, expired, certificate fetch)
    or ValueError for an empty token.
    """
    return auth.verify_id_token(token, app=firebase_app())
