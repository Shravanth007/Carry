"""What an account has spent, and whether it may spend more."""

from datetime import UTC, datetime

import pytest

from app.services import plans, usage
from app.services.users import CarryUser
from tests.helpers import TestUsage

JANUARY = datetime(2026, 1, 15, 12, 0, tzinfo=UTC)
FEBRUARY = datetime(2026, 2, 1, 0, 0, tzinfo=UTC)


def account(plan: str = plans.FREE) -> CarryUser:
    return CarryUser(
        uid="ada", email=None, created_at=JANUARY, blocked=False, plan=plan
    )


class TestMonths:
    def test_a_month_is_named_after_its_utc_month(self):
        assert usage.month_of(JANUARY) == "2026-01"

    def test_local_time_does_not_decide_it(self):
        """A month that starts at a different moment for each person is a month
        you can start twice by flying."""
        late_in_india = datetime(2026, 2, 1, 4, 30, tzinfo=UTC)  # 10:00 IST

        assert usage.month_of(late_in_india) == "2026-02"


class TestSpending:
    def test_a_new_account_has_spent_nothing(self):
        counted = TestUsage()

        assert usage.spent(counted, account(), JANUARY).used_seconds == 0

    def test_what_is_left_comes_from_the_plan(self):
        counted = TestUsage()
        usage.record(counted, "ada", 600, JANUARY)

        free = usage.spent(counted, account(plans.FREE), JANUARY)
        paid = usage.spent(counted, account(plans.PLUS), JANUARY)

        assert free.left_seconds == plans.PLANS["free"].transcription_seconds - 600
        assert paid.left_seconds == plans.PLANS["plus"].transcription_seconds - 600

    def test_spending_past_the_allowance_leaves_nothing_rather_than_a_debt(self):
        counted = TestUsage()
        usage.record(counted, "ada", 99_999, JANUARY)

        assert usage.spent(counted, account(), JANUARY).left_seconds == 0

    def test_a_new_month_starts_again(self):
        """A new month is a new row. Nothing has to run on a schedule to reset
        a counter, and last month stays readable."""
        counted = TestUsage()
        usage.record(counted, "ada", 3000, JANUARY)

        assert usage.spent(counted, account(), FEBRUARY).used_seconds == 0
        assert usage.spent(counted, account(), JANUARY).used_seconds == 3000

    def test_accounts_are_counted_apart(self):
        counted = TestUsage()
        usage.record(counted, "ada", 600, JANUARY)

        grace = CarryUser(
            uid="grace", email=None, created_at=JANUARY, blocked=False
        )
        assert usage.spent(counted, grace, JANUARY).used_seconds == 0

    def test_nothing_is_recorded_for_nothing(self):
        counted = TestUsage()

        usage.record(counted, "ada", 0, JANUARY)
        usage.record(counted, "ada", -5, JANUARY)

        assert counted.rows == {}


class TestTheQuota:
    def test_within_the_allowance_is_allowed(self):
        counted = TestUsage()

        usage.check(counted, account(), 60, JANUARY)  # must not raise

    def test_past_it_is_refused_before_the_money_is_spent(self):
        counted = TestUsage()
        usage.record(counted, "ada", 3590, JANUARY)

        with pytest.raises(usage.OverQuota) as refused:
            usage.check(counted, account(), 60, JANUARY)

        assert refused.value.allowed == 3600

    def test_the_paid_plan_allows_far_more(self):
        counted = TestUsage()
        usage.record(counted, "ada", 3590, JANUARY)

        usage.check(counted, account(plans.PLUS), 60, JANUARY)  # must not raise

    def test_an_unknown_plan_falls_back_to_free(self):
        """A renamed or removed plan must not hand out an unlimited allowance.
        The safe direction is asking someone to upgrade, not spending money we
        didn't mean to."""
        counted = TestUsage()
        usage.record(counted, "ada", 3590, JANUARY)

        with pytest.raises(usage.OverQuota):
            usage.check(counted, account("enterprise_v3"), 60, JANUARY)


class TestAnExpiredPlan:
    """A missed expiry webhook must not leave somebody on the paid allowance
    for ever. Stores drop webhooks - the reconciliation path exists because
    they do - so the end date is part of the answer, not just the plan name."""

    def test_a_plan_whose_period_has_passed_allows_what_free_allows(self):
        counted = TestUsage()
        expired = CarryUser(
            uid="ada",
            email=None,
            created_at=JANUARY,
            blocked=False,
            plan=plans.PLUS,
            plan_until=datetime(2026, 1, 1, tzinfo=UTC),
        )

        allowed = usage.spent(counted, expired, JANUARY).allowed_seconds

        assert allowed == plans.PLANS["free"].transcription_seconds

    def test_a_plan_still_running_allows_the_paid_amount(self):
        counted = TestUsage()
        current = CarryUser(
            uid="ada",
            email=None,
            created_at=JANUARY,
            blocked=False,
            plan=plans.PLUS,
            plan_until=datetime(2027, 1, 1, tzinfo=UTC),
        )

        allowed = usage.spent(counted, current, JANUARY).allowed_seconds

        assert allowed == plans.PLANS["plus"].transcription_seconds

    def test_and_the_quota_uses_the_same_answer(self):
        counted = TestUsage()
        usage.record(counted, "ada", 3590, JANUARY)
        expired = CarryUser(
            uid="ada",
            email=None,
            created_at=JANUARY,
            blocked=False,
            plan=plans.PLUS,
            plan_until=datetime(2026, 1, 1, tzinfo=UTC),
        )

        with pytest.raises(usage.OverQuota):
            usage.check(counted, expired, 60, JANUARY)
