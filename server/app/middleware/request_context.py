import logging
import re
import time
import uuid

from fastapi import Request

log = logging.getLogger("carry.request")

# Only accept simple IDs from clients so they can't inject lines into logs.
_VALID_ID = re.compile(r"[A-Za-z0-9-]{1,64}")


async def request_context(request: Request, call_next):
    """Gives each request an ID (X-Request-ID) and logs one line per request.

    The app can send its own ID to match app logs with server logs.
    Headers are never logged, so tokens stay out of the logs.
    """
    incoming = request.headers.get("X-Request-ID", "")
    request_id = incoming if _VALID_ID.fullmatch(incoming) else uuid.uuid4().hex
    request.state.request_id = request_id

    start = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - start) * 1000

    response.headers["X-Request-ID"] = request_id
    log.info(
        "%s %s %s %.0fms id=%s",
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
        request_id,
    )
    return response
