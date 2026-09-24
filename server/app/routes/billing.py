import logging

from fastapi import APIRouter, Header, HTTPException, Request

from app.services import billing, db

log = logging.getLogger("carry.billing")
router = APIRouter(tags=["billing"])


@router.post("/billing/webhook", status_code=204)
async def webhook(
    request: Request,
    authorization: str | None = Header(default=None),
) -> None:
    """Where the store tells us a plan changed.

    Open to the internet, so the secret is the only thing that makes an event
    ours - checked before the body is even read. A 204 means "applied, or
    already applied": either way there is nothing for the sender to retry.
    """
    try:
        billing.check_secret(authorization)
    except billing.NotOurs:
        # Deliberately vague: an attacker probing this shouldn't learn whether
        # a secret is configured, only that theirs isn't it.
        raise HTTPException(401, "Not authorised.") from None
    except billing.NotConfigured as e:
        log.error("%s", e)
        raise HTTPException(503, "Billing isn't set up on this server.") from None

    payload = await request.json()
    try:
        event = billing.read(payload)
    except ValueError as e:
        log.warning("unreadable billing event: %s", e)
        raise HTTPException(400, "That isn't an event we can read.") from None

    try:
        applied = billing.apply(event)
    except db.NotConfigured as e:
        log.error("%s", e)
        raise HTTPException(503, "Carry isn't set up to store accounts yet.") from None
    except db.Unavailable as e:
        # A 503 asks the store to send it again. Dropping it would lose a
        # payment somebody made.
        log.error("%s", e)
        raise HTTPException(503, "Couldn't record that right now.") from None

    log.info("billing event %s (%s) %s", event.id, event.kind,
             "applied" if applied else "was already applied")
