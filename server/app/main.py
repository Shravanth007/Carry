import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.core import config  # loads .env before anything else reads env vars
from app.middleware.body_size import body_size_limit
from app.middleware.request_context import request_context
from app.routes import health, users
from app.services import db, firebase_auth
from app.utils.logging import setup_logging

setup_logging(config.LOG_LEVEL)
log = logging.getLogger("carry")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Say what's missing at startup rather than letting the first signed-in
    # request be the one that finds out.
    try:
        firebase_auth.firebase_app()
    except firebase_auth.NotConfigured as e:
        log.error("%s", e)
    db.start()
    yield
    db.stop()


app = FastAPI(title="Carry", lifespan=lifespan)
# Outermost first: refuse an oversized body before anything reads it.
app.middleware("http")(request_context)
app.middleware("http")(body_size_limit)
app.include_router(health.router)
app.include_router(users.router)
