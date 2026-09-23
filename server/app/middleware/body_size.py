from fastapi import Request
from fastapi.responses import JSONResponse

from app.core import config


async def body_size_limit(request: Request, call_next):
    """Refuses a body bigger than the cap, before reading any of it.

    Audio goes straight to S3 with a presigned URL, so nothing legitimate
    posts a large body here. A public repo means anyone can craft a request,
    and without this one of them can fill the server's memory.
    """
    declared = request.headers.get("content-length")
    if declared is not None:
        try:
            if int(declared) > config.MAX_BODY_BYTES:
                return JSONResponse(
                    {"detail": "That request is too large."},
                    status_code=413,
                )
        except ValueError:
            return JSONResponse(
                {"detail": "Bad Content-Length header."}, status_code=400
            )
    return await call_next(request)
