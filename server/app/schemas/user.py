from pydantic import BaseModel


class UserOut(BaseModel):
    uid: str
    email: str | None = None
