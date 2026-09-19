from fastapi import APIRouter

from app.schemas.health import HealthOut

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthOut)
def health():
    """Open endpoint: says the server is up, without needing a sign-in."""
    return HealthOut(ok=True)
