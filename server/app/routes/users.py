import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from app.dependencies.auth import CurrentUser
from app.schemas.user import UserOut
from app.services import db, usage
from app.services.usage import UsageStore

log = logging.getLogger("carry.users")
router = APIRouter(tags=["users"])


@router.get("/me", response_model=UserOut)
def me(
    user: CurrentUser,
    counted: Annotated[UsageStore, Depends(usage.store)],
):
    """Who the server thinks you are. Handy for checking sign-in end to end."""
    try:
        left = usage.spent(counted, user).left_seconds
    except (db.NotConfigured, db.Unavailable) as e:
        # The account lookup already succeeded, so this is the database having
        # a moment. A 503 says try again; a 500 says nothing at all.
        log.error("%s", e)
        raise HTTPException(503, "Couldn't read your plan. Try again.") from None
    return UserOut(
        uid=user.uid,
        email=user.email,
        since=user.created_at,
        plan=user.effective_plan,
        plan_until=user.plan_until,
        seconds_left=left,
    )
