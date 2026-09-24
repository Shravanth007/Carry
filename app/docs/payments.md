# Payments

> **Status: half built.**
> The server side exists — plans, quotas, the webhook and the ledger, with 44
> tests. What does **not** exist: the RevenueCat SDK in the app, the paywall
> screen, and anything that meters transcription, because transcription itself
> isn't built yet.
>
> **Nothing in Carry can charge anyone.** Google takes the money and RevenueCat
> reports it; the server only ever reads "this account has the `plus`
> entitlement until Tuesday" and writes it down.

Like [auth.md](auth.md), this covers both halves: the app shows the plan, the
server decides what it means.

## What is being sold

The only thing that costs money per person is **transcription** — Groq is about
$0.04 an hour of audio — and a little storage. So the unit is transcription
time, not "number of notes", which tracks nothing real.

| | Free | Carry Plus |
|---|---|---|
| Transcription | 60 minutes a month | 20 hours a month |
| Audio kept | 30 days, then the audio goes and the transcript stays | while subscribed |
| Price | — | ~₹199 / $2.99 a month, 7-day trial |

At 20 hours, Groq costs about $0.80 and S3 about a cent. The free tier costs
about 4 cents per active person, which is cheap enough that the quota exists to
stop a script, not to protect a margin.

## Why Play Billing, through RevenueCat

**Google Play requires Play Billing for digital goods.** Stripe in a webview is
how an app gets removed from the store. Play is also the merchant of record, so
Google handles GST and invoices — with Stripe that would be ours to do.

RevenueCat sits between Play and our server: it validates receipts with Google,
tracks renewals and expiries, and tells us when an **entitlement** changes. We
never parse a receipt, and iOS costs nothing extra when it lands.

## The one idea to hold on to

**Check an entitlement, never a product.**

`plus` is an entitlement. `carry_plus_monthly` is a product. Products change —
a yearly plan, a price rise, a regional SKU — and every `if (sku == ...)` in the
codebase breaks the day one is added. Entitlements don't change.

The same idea is why RevenueCat's **Offerings** are worth using: price,
packaging and trials are dashboard settings, so none of them need an app update.

## How features are gated

The honest rule, which decides every row below:

> **Gate new cost. Never gate what someone already has.**

Recording, playing back your own audio, reading transcripts you already have,
and exporting your data are never gated. Charging to reach your own words is a
dark pattern, and for exports, a legally uncomfortable one.

| Feature | Free | Plus | Gate enforced | Why there |
|---|---|---|---|---|
| Record on the phone | ✅ unlimited | ✅ | — | Costs us nothing. Never gated |
| Import a file | ✅ unlimited | ✅ | — | Costs us nothing until it's transcribed |
| Play back your audio | ✅ | ✅ | — | It's already yours |
| Read existing transcripts | ✅ | ✅ | — | Already paid for, already yours |
| Export notes and audio | ✅ | ✅ | — | Never gated, on principle |
| **Transcription** | 60 min/month | 20 h/month | **Server**, before Groq is called | This is the actual bill |
| **Upload to Carry cloud** | within the audio-retention window | ✅ | **Server**, before a presigned URL is signed | A signed URL is storage already spent |
| Audio retention | 30 days | while subscribed | **Server**, a sweep job | Storage cost accrues quietly |
| Search across notes | ✅ | ✅ | — | Local, costs nothing |
| **MCP access** | ❌ | ✅ | **Server**, at the MCP endpoint | Server work per call, and it's the power-user feature |
| Backup to Google Drive | ✅ | ✅ | — | Their Drive, their storage |

Two gates that matter, both server-side, both **before** the money is spent:
before signing an upload URL, and before calling Groq.

The app's copy of the numbers (`lib/limits.dart`) exists so someone hears "no"
before a long upload — not to enforce anything. As everywhere else in Carry, the
server decides and the app is a courtesy.

### What happens when the quota runs out

The recording **still saves**. The note appears with "Waiting for next month, or
upgrade" where the transcript would be, and transcribes itself when the month
rolls over or the plan changes.

Never lose someone's audio over billing. This is the same rule that stopped an
hour-long recording being deleted for finishing a few milliseconds late.

## Where the truth lives

`users` gains three columns:

```sql
plan        TEXT NOT NULL DEFAULT 'free',   -- 'free' | 'plus'
plan_until  TIMESTAMPTZ,                    -- end of the current paid period
plan_source TEXT                            -- 'play' | 'granted'
```

Two new tables:

```sql
-- Monthly counters. A new month is a new row, never a job that resets a total.
usage (uid, month, seconds_transcribed, PRIMARY KEY (uid, month))

-- The ledger. event_id as the primary key IS the idempotency: a duplicate
-- delivery hits a unique violation and is dropped, with no check-then-insert
-- race to get wrong.
billing_events (event_id PRIMARY KEY, uid, kind, received_at, payload_hash)
```

And one place that says what a plan allows, so no number is ever written twice:

```python
# server/app/services/plans.py
PLANS = {
    "free": {"transcription_seconds": 3600,  "keep_audio_days": 30},
    "plus": {"transcription_seconds": 72000, "keep_audio_days": None},
}
```

## The webhook

`POST /billing/webhook`, secured by the shared secret RevenueCat sends in an
`Authorization` header. What each event does:

| Event | What we do |
|---|---|
| `INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION` | `plan = 'plus'`, `plan_until` = the period end |
| `CANCELLATION` | Nothing yet — they keep Plus until `plan_until`. They paid for it |
| `EXPIRATION` | `plan = 'free'` **only if the period we hold has actually ended** — see below |
| `BILLING_ISSUE` | Keep Plus, flag it: Play retries for days, and the app shows a banner |
| `PRODUCT_CHANGE` | Re-read the entitlement, don't infer from the product |
| `TRANSFER` | **Move** the plan from the old uid to the new one, keeping the source row's `plan_until` — a transfer payload is only `transferred_from` and `transferred_to`, both **arrays** of app user IDs, with no period of its own. One Play account, two Google logins — easy to forget and wrong in a way people notice |
| `REFUND` | `plan = 'free'` immediately |

**An event we accept but cannot act on leaves a note.** `billing_events.problem`
says why — today only a transfer that doesn't name one account on each side.
Acknowledging is the right answer to the store (a redelivery is the same
payload), but somebody's paid access may be on the wrong account, so:

```sql
SELECT event_id, kind, received_at, problem
  FROM billing_events WHERE problem IS NOT NULL ORDER BY received_at;
```

Fixing one is a query and a `UPDATE users SET plan ...` by hand. That is the
right amount of machinery for a list that should be empty: an admin screen
nobody opens is a second way to change a plan, and a second way to get it
wrong. Build one when real money is moving and the list stops being empty.

**Only ever move `plan_until` forwards, and that includes downgrades.**
Webhooks arrive out of order. An old `RENEWAL` landing after a newer one must
not shorten somebody's month — and, the trap, an old `EXPIRATION` arriving after
a newer `RENEWAL` must not revoke a plan that has since been paid for.

So an expiry is not "set free", it is: *has the period we hold ended?*

```python
if event.kind == "EXPIRATION" and event.period_end >= user.plan_until:
    user.plan = "free"        # the period we knew about is the one that ended
# otherwise: a newer renewal already moved us past it. Ignore.
```

Every event carries the period it refers to, and that — not arrival order — is
what decides. Reconciliation is the backstop: when in doubt, re-read the
subscriber from RevenueCat rather than reasoning from the last event seen.

## Missed webhooks: the failure that actually happens

A dropped webhook means someone paid and didn't get it, and they will not
believe the app when it says otherwise. So there is a reconciliation path, not
just a listener:

- RevenueCat's REST API (`GET /subscribers/{uid}`) is the truth we can re-read.
- Call it when the app reports an entitlement the server doesn't have —
  the app's SDK noticing first is a signal, not a grant.
- Sweep accounts whose `plan_until` passed in the last day, in case the
  `RENEWAL` never arrived.

## The app side

One facade, `lib/billing/billing.dart` — the only file that imports
`purchases_flutter`, exactly as `Auth`, `Api` and `Analytics` are the only doors
to their own areas.

**Identity has to match.** `Purchases.logIn(uid)` on sign-in and `logOut()` on
sign-out, in the same places `Analytics.identify` and `reset` already sit. If
RevenueCat's user ID isn't the Firebase uid, the webhook can't say whose plan
changed.

**The SDK is for the screen, not for permission.**
`customerInfo.entitlements.active['plus']` makes the paywall respond the instant
a purchase completes. It grants nothing. The server sets `plan` from the
webhook, and when the two disagree, the server is right.

```
Settings
  └─ Plan          Free · 42 min left this month   >
       └─ Plan screen
            Free   60 min/month           [current]
            Plus   20 hours/month         [Start free trial]
            · Restore purchases
            · Manage subscription → opens Play
```

Four states the plan screen has to handle, and they're where these screens
usually go wrong: **free**, **plus**, **pending** (Play can take seconds, and a
spinner that never resolves is the common bug), and **grace period** —
"we couldn't renew your plan" rather than silently dropping to free.

## Worth having, in the order I'd add them

1. **A 7-day free trial** — Play and RevenueCat dashboard settings, **no code**,
   and the biggest single lever on conversion.
2. **`plan_source = 'granted'`** — one `UPDATE` gives a friend, a reviewer or a
   support case Plus. Free to build, invaluable the first time it's needed.
3. **A usage meter in settings** — "42 of 60 minutes left". Answers the support
   question before it is asked.
4. **The grace-period banner** — a card expiring shouldn't feel like a bug.
5. **Reconciliation** — above. Not optional.

Later, and only if they earn it: an annual plan (dashboard only), a one-off
"5 hours" top-up (teaches consumables, but brings its own refund and crediting
rules).

Deliberately not: family sharing, referrals, more tiers, web checkout. Each is a
whole failure surface for an app with one feature.

## Analytics

The wiring already exists; these are the events worth adding:

`paywall_seen{from}` · `upgrade_started` · `upgrade_completed{plan}` ·
`upgrade_abandoned` · `quota_hit{minutes_used}` · `plan_expired` ·
`restore_used`.

`quota_hit` is the one that says whether the free tier is set right — the same
job `import_rejected{too_large}` does for the size cap.

## Tests

**Server:** a bad signature is refused · a duplicate `event_id` is dropped · an
out-of-order event can't move `plan_until` backwards · `TRANSFER` moves a plan
rather than copying it · expiry downgrades · the quota blocks before a URL is
signed and before Groq is called · a month boundary resets the counter ·
reconciliation fixes an account a webhook never reached.

**App:** a purchase updates the screen · cancelling shows nothing alarming ·
restore works after a reinstall · expired falls back to free · **when the SDK
and the server disagree, the server wins** · running out mid-recording still
saves the audio.

Each one gets checked by removing the thing it tests, as usual.

## What's needed before any of this can run

1. **RevenueCat**: project + Play app → **public SDK key** (app) and **webhook
   secret** (server).
2. **Play Console → API access**: a service account JSON **uploaded to
   RevenueCat**, so it can verify purchases with Google. This is the step people
   miss, and nothing works without it.
3. **Play Console**: subscription `carry_plus_monthly`, plus a **licence tester**
   account for sandbox purchases.
4. **A privacy policy URL** — Play requires one before billing works at all,
   even in test.
5. Confirmation of price, tier limits and trial length.

`server/.env` would gain `REVENUECAT_WEBHOOK_SECRET` and `REVENUECAT_API_KEY`
(the second only for reconciliation). The app's SDK key is a **build flag**,
like PostHog's, because it is public by design.

## Build order, and the honest caveat

1. Schema, `plans.py`, `/me` returning plan and minutes left — invisible, safe to
   land first.
2. **Quota enforcement at upload and transcription.** Worth doing with or
   without payments: it's what stops one account spending an unbounded amount of
   somebody's Groq key.
3. Plan screen and settings row, showing free only.
4. RevenueCat, webhook, purchase flow.

**Payments have nothing to meter until transcription exists.** The real order is
Drift → upload → transcription → this. Steps 1 and 2 are the parts that pay for
themselves early; 3 and 4 wait for the accounts above.
