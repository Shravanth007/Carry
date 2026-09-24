from datetime import datetime

from pydantic import BaseModel


class UserOut(BaseModel):
    uid: str
    email: str | None = None

    """When this account first used Carry, not when it joined Google."""
    since: datetime

    #: 'free' or 'plus'.
    plan: str
    #: When the paid period ends. Null on free.
    plan_until: datetime | None = None
    #: Transcription left this month. The app shows it; the server enforces it.
    seconds_left: int
