import logging

from fastapi.responses import JSONResponse

from app.core import config

log = logging.getLogger("carry.body")


class _TooLarge(Exception):
    """The body went past the cap while it was being read."""


class BodySizeLimit:
    """Refuses a body bigger than the cap, without trusting what it claims.

    Audio goes straight to S3 with a presigned URL, so nothing legitimate posts
    a large body here. A public repo means anyone can craft a request, and
    without this one of them can fill the server's memory.

    Two checks, because one isn't enough:

    * `Content-Length`, before a single byte is read, so an honest oversized
      request is turned away immediately.
    * the bytes actually arriving, because a chunked request carries no
      `Content-Length` at all. Trusting the header alone means the limit is
      whatever the client says it is.

    Written as plain ASGI rather than a `BaseHTTPMiddleware` function: this has
    to sit between the app and its `receive`, which a function middleware never
    sees.
    """

    def __init__(self, app, max_bytes: int = config.MAX_BODY_BYTES):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        declared = _header(scope, b"content-length")
        if declared is not None:
            try:
                if int(declared) > self.max_bytes:
                    await _refuse(send, 413, "That request is too large.")
                    return
            except ValueError:
                await _refuse(send, 400, "Bad Content-Length header.")
                return

        read = 0
        answering = False

        async def counted_receive():
            nonlocal read
            message = await receive()
            if message["type"] == "http.request":
                read += len(message.get("body", b""))
                if read > self.max_bytes:
                    raise _TooLarge
            return message

        async def watched_send(message):
            nonlocal answering
            if message["type"] == "http.response.start":
                answering = True
            await send(message)

        try:
            await self.app(scope, counted_receive, watched_send)
        except _TooLarge:
            log.warning("body over the cap on %s", scope.get("path"))
            # Only if nothing has been sent yet. Once the route has started
            # answering, its own response is already on the wire.
            if not answering:
                await _refuse(send, 413, "That request is too large.")


def _header(scope, name: bytes) -> bytes | None:
    for key, value in scope.get("headers", []):
        if key.lower() == name:
            return value
    return None


async def _refuse(send, status: int, detail: str) -> None:
    response = JSONResponse({"detail": detail}, status_code=status)
    await response({"type": "http"}, _no_body, send)


async def _no_body():
    return {"type": "http.request", "body": b"", "more_body": False}
