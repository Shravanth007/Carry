"""What each plan allows.

One table, so no allowance is ever written twice. Everything that asks "may
they?" asks here, and nothing else hard-codes a number.

The unit is transcription time, because that is the only thing that costs money
per person: Groq charges by the hour of audio. Counting notes would measure
something we don't pay for.
"""

from dataclasses import dataclass

FREE = "free"
PLUS = "plus"

# The entitlement RevenueCat grants, not the product someone bought. Products
# change - a yearly plan, a price rise, a regional SKU - and code that checks a
# product breaks the day one is added.
PLUS_ENTITLEMENT = "plus"


@dataclass(frozen=True)
class Plan:
    name: str
    transcription_seconds: int
    #: None means kept for as long as the account is.
    keep_audio_days: int | None


PLANS = {
    FREE: Plan(name=FREE, transcription_seconds=3600, keep_audio_days=30),
    PLUS: Plan(name=PLUS, transcription_seconds=72000, keep_audio_days=None),
}


def allowance(plan: str) -> Plan:
    """What this plan may do. An unknown plan gets the free one.

    Unknown happens when a plan is renamed or removed while accounts still
    carry the old name. Falling back to free is the safe direction: the worst
    case is somebody being asked to upgrade, not somebody spending money we
    didn't mean to spend.
    """
    return PLANS.get(plan, PLANS[FREE])
