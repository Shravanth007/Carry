import logging

from fastapi import FastAPI

from app.core import config  # loads .env before anything else reads env vars
from app.middleware.request_context import request_context
from app.routes import health, users
from app.services import firebase_auth
from app.utils.logging import setup_logging

setup_logging(config.LOG_LEVEL)

# Say it at startup rather than letting the first signed-in request fail.
try:
    firebase_auth.firebase_app()
except firebase_auth.NotConfigured as e:
    logging.getLogger("carry").error("%s", e)

app = FastAPI(title="Carry")
app.middleware("http")(request_context)
app.include_router(health.router)
app.include_router(users.router)
