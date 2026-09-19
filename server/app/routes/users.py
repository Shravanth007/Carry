from fastapi import APIRouter

from app.dependencies.auth import CurrentUser
from app.schemas.user import UserOut

router = APIRouter(tags=["users"])


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser):
    return UserOut(uid=user["uid"], email=user.get("email"))
