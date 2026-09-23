import threading
import time
from collections import defaultdict, deque

from app.core import config


class TooMany(Exception):
    """Over the limit. Carries how long to wait, for Retry-After."""

    def __init__(self, retry_after: int):
        super().__init__("too many requests")
        self.retry_after = retry_after


class RateLimiter:
    """How many calls one account may make per minute.

    The app cannot be trusted to limit itself: anyone can build their own
    client against a public repo. This is the only place the limit is real.

    # ponytail: counted in this process's memory, so two server instances
    # would allow two windows. Move the counting into Postgres or Redis when
    # there is more than one instance.
    """

    def __init__(self, per_minute: int = config.RATE_LIMIT_PER_MINUTE):
        self.per_minute = per_minute
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        # FastAPI runs a `def` dependency in a worker thread, so requests for
        # the same account really do arrive here at the same time. Counting
        # and allowing have to happen as one step, or a burst of threads each
        # sees room and they all get through.
        # ponytail: one lock for every account. It is held for a few
        # microseconds; give each uid its own only if it ever shows up in a
        # profile.
        self._lock = threading.Lock()

    def check(self, uid: str, now: float | None = None) -> None:
        """Raises TooMany when this account is over its limit."""
        now = now if now is not None else time.monotonic()
        window_start = now - 60
        with self._lock:
            hits = self._hits[uid]
            while hits and hits[0] <= window_start:
                hits.popleft()
            if len(hits) >= self.per_minute:
                raise TooMany(retry_after=max(1, int(60 - (now - hits[0]))))
            hits.append(now)

    def forget(self, uid: str) -> None:
        with self._lock:
            self._hits.pop(uid, None)


_limiter = RateLimiter()


def limiter() -> RateLimiter:
    """Dependency, so tests can use their own limits."""
    return _limiter
