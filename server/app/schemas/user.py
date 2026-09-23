from datetime import datetime

from pydantic import BaseModel


class UserOut(BaseModel):
    uid: str
    email: str | None = None

    """When this account first used Carry, not when it joined Google."""
    since: datetime
