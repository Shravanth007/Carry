from typing import Annotated

from fastapi import APIRouter, Depends

from app.dependencies.auth import CurrentUser
from app.schemas.user import UserOut
from app.services import usage
from app.services.usage import UsageStore

router = APIRouter(tags=["users"])


@router.get("/me", response_model=UserOut)
def me(
    user: CurrentUser,
    counted: Annotated[UsageStore, Depends(usage.store)],
):
    """Who the server thinks you are. Handy for checking sign-in end to end."""
    left = usage.spent(counted, user).left_seconds
    return UserOut(
        uid=user.uid,
        email=user.email,
        since=user.created_at,
        plan=user.plan,
        plan_until=user.plan_until,
        seconds_left=left,
    )
