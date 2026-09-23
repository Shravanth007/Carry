from fastapi import APIRouter

from app.dependencies.auth import CurrentUser
from app.schemas.user import UserOut

router = APIRouter(tags=["users"])


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser):
    """Who the server thinks you are. Handy for checking sign-in end to end."""
    return UserOut(uid=user.uid, email=user.email, since=user.created_at)
