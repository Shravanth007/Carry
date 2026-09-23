# Security

Carry is a public repository. Anyone can read how the API works, build their
own client, and call it. That is fine, and it settles the design question:

> **The app is never trusted. Every limit lives on the server.**

The Flutter app's checks exist to give people a good message quickly. They are
courtesies, not defences. Anything that actually matters is enforced here.

## The one rule

**The user id comes from a verified Firebase token. Never from anywhere else.**

Not the request body, not a header, not a query string, not a file path. If a
request could name someone else's id, it would only take one forged field to
read another person's notes.

```python
@router.get("/recordings")
def list_recordings(user: CurrentUser):
    rows = fetch(owner_uid=user.uid)   # from the token, always
```

## What every protected request goes through

`CurrentUser` runs these in order, and nothing can skip them:

| # | Check | Fails with |
|---|---|---|
| 1 | A real, unexpired Firebase token for **this** project | `401` |
| 2 | The token carries a uid | `401` |
| 3 | The account exists here, created on first sight | `503` if the database is missing |
| 4 | The account isn't blocked | `403` |
| 5 | The account is inside its rate limit | `429` + `Retry-After` |

`/health` is the only open endpoint: uptime checks call it often and it says
nothing about anyone.

### Why verification is real

`verify_id_token` checks the signature against Google's public keys, the
expiry, and that the issuer and audience are our Firebase project. A token
minted by another Firebase project, a forged one, or an expired one are all
refused. This is not something a client can talk its way past.

## Limits, and why each is here

Set in `app/core/config.py`, overridable by environment variable.

| Limit | Default | Why the app can't own it |
|---|---|---|
| `RATE_LIMIT_PER_MINUTE` | 60 per account | A modified client has no rate limiter |
| `MAX_BODY_BYTES` | 1 MB | Audio goes straight to S3; nothing here needs a big body. Without this, one request can exhaust memory |
| `DB_MAX_CONNECTIONS` | 5 | Neon's free tier has a modest budget; runaway connections take the service down |

**Rate limiting is per process today.** It counts in memory, so two server
instances would allow two windows. That's marked with a `ponytail:` comment
and moves to Postgres or Redis when there is more than one instance.

## Blocking an account

There is no admin UI, and there doesn't need to be:

```sql
UPDATE users SET blocked = true WHERE uid = '<the uid>';
```

Their next request gets `403`. Firebase can also disable the account itself,
which stops new tokens being issued; this stops the ones already out there
from doing anything useful.

## Rules for endpoints that don't exist yet

When recordings and uploads land, these are not optional.

**Quotas, checked before anything is created:**
- recordings per day per account,
- total stored bytes per account,
- maximum single file size, and maximum duration.

Check the quota **before** issuing a presigned URL. A URL handed out is
storage already spent.

**Presigned uploads must be narrow.** A signed URL is a key to your bucket,
so each one is scoped to:
- exactly one object key, always under `audio/{uid}/` or `temp/{uid}/`,
- one content type,
- a **content-length range**, so the cap is enforced by S3 itself,
- a short expiry, minutes not hours.

**Never take the object key from the client.** The server builds it from the
uid in the token and the recording id it created. Otherwise a crafted key
writes into someone else's folder.

**Recompute, don't believe.** Duration and size arrive as claims from the
client. Confirm them from the uploaded object before they count towards a
quota or a bill.

**A missing row and a forbidden row both answer `404`.** Replying `403` for
someone else's recording confirms that the id exists.

## Secrets

Nothing secret has ever been committed, and `git log` over the whole history
confirms it: no `.env`, no service account key, no access key, no connection
string.

| Secret | Where it lives |
|---|---|
| Firebase service account key | `server/secrets/`, git-ignored |
| Groq API key, database URL, AWS keys | `server/.env`, git-ignored |
| Firebase Android API key | **Public by design**, in `google-services.json` |

That last one surprises people. A Firebase client API key identifies the
project; it is not a password. What protects the project is that Google
sign-in requires the app's SHA fingerprint, and that this server checks every
token. Two things worth doing in the console anyway:

1. **App Check** with Play Integrity, so requests can be tied to the real app
   rather than a script holding a stolen token.
2. **Restrict the Android API key** to package `com.carry.carry` and the
   release SHA-1, in Google Cloud → Credentials.

## Before the server is deployed

Not needed while it runs on a laptop, needed the day it has a public address:

- **HTTPS only.** Tokens in a header over plain HTTP are tokens given away.
- **CORS stays off.** No browser origin needs this API. Adding
  `CORSMiddleware` without a strict allow-list opens it to every website.
- **Trusted hosts**, so the service only answers on its own hostname.
- **Rate limiting moved out of process**, as above.
- **Log with care.** Request IDs and status codes yes; tokens, emails and
  audio contents no. The current access log deliberately logs no headers.

## Testing this

Tests never touch a real database or Firebase. `tests/conftest.py` swaps in a
test verifier, in-memory accounts and a fresh rate limiter, so every rule
above can be tested without a secret in CI — which is also why CI holds no
credentials at all.

Covered today: no token, wrong scheme, empty token, forged, expired, keys
unreachable, misconfigured server, a token without a uid, a blocked account,
account creation and reuse, two accounts staying separate, the rate limit and
its window, per-account isolation, and the body size cap.
