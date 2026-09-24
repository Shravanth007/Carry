"""Keeping the server up when someone points a loop at it.

Every other limit Carry has is per account, which means none of them apply
until a token has been verified. A script with no account, or with junk tokens,
was unlimited. These two are the ones that don't need to know who you are.

See `docs/load.md` for the order they run in and what each is for.
"""

import logging

from fastapi.responses import JSONResponse

from app.core import config
from app.services.rate_limit import TooMany, ip_limiter

log = logging.getLogger("carry.load")


class LoadShedder:
    """Refuses work when there is already too much in flight.

    Queueing is how a server dies slowly: requests pile up behind the database
    pool, each holding memory and a worker, until nothing finishes. Refusing
    immediately keeps the ones already running alive, which is the only useful
    thing to do when there is more work than capacity.

    The counter needs no lock: it is read and written in the same event loop
    with no `await` in between, so nothing can interleave.
    """

    def __init__(self, app, most: int = config.MAX_IN_FLIGHT):
        self.app = app
        self.most = most
        self.in_flight = 0

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        if self.in_flight >= self.most:
            log.warning(
                "shedding %s, %d already in flight",
                scope.get("path"),
                self.in_flight,
            )
            await _refuse(
                send,
                503,
                "Carry is busy right now. Try again in a moment.",
                retry_after=1,
            )
            return

        self.in_flight += 1
        try:
            await self.app(scope, receive, send)
        finally:
            self.in_flight -= 1


async def ip_rate_limit(request, call_next):
    """Limits how often one address may call, signed in or not.

    This is the only limit that applies to `/health` and to a request whose
    token turns out to be rubbish, so it is what stands between the server and
    a script that has no account at all.
    """
    where = client_address(request)
    try:
        ip_limiter().check(where)
    except TooMany as e:
        log.warning("rate limited %s on %s", where, request.url.path)
        return JSONResponse(
            {"detail": "Too many requests. Slow down and try again shortly."},
            status_code=429,
            headers={"Retry-After": str(e.retry_after)},
        )
    return await call_next(request)


def client_address(request) -> str:
    """Who to count this request against.

    `X-Forwarded-For` is a header, so anyone can write anything in it: trusting
    it without a proxy in front would let one script pretend to be a thousand
    addresses and skip the limit entirely. It is used only when
    `TRUST_PROXY_HEADER` says something we control sets it, and then the **last**
    entry is taken, because that is the one our own proxy wrote — the earlier
    ones came from the client.
    """
    if config.TRUST_PROXY_HEADER:
        forwarded = request.headers.get("X-Forwarded-For", "")
        hops = [hop.strip() for hop in forwarded.split(",") if hop.strip()]
        if hops:
            return hops[-1]
    client = request.client
    return client.host if client else "unknown"


async def _refuse(
    send, status: int, detail: str, retry_after: int | None = None
) -> None:
    headers = {"Retry-After": str(retry_after)} if retry_after else None
    response = JSONResponse({"detail": detail}, status_code=status, headers=headers)
    await response({"type": "http"}, _no_body, send)


async def _no_body():
    return {"type": "http.request", "body": b"", "more_body": False}
