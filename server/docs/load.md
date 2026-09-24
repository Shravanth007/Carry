# Staying up

What stops one person, or one script, taking Carry down — and, just as
importantly, what doesn't, so nobody assumes cover that isn't there.

## The threat we are actually defending against

Carry is a public repository with a documented API. The realistic attack is
**someone pointing a loop at it**: a script that found the repo, a bad retry in
a fork, or one account behaving badly.

It is **not** a distributed denial of service. Nothing written in Python can
stop a saturated network pipe — by the time packets reach the app, the damage
is done. That is what the edge is for, and it's listed at the bottom.

## The hole this closed

Every limit Carry had was keyed on the **account**, which means none of them
applied until a token had been verified:

- `/health` was open and unlimited;
- a request with a junk token was unlimited, and each one cost a signature
  check before being refused;
- nothing capped how many requests could be in flight at once, so the five
  database connections became the queue and everything waited behind them.

A script with no account at all was therefore unlimited. The two limits below
are the ones that don't need to know who you are.

## What happens to a request, in order

Starlette runs the **last** registered middleware outermost, so `main.py` reads
inside-out. What a request meets, in order:

| # | Layer | Refuses with | What it is for |
|---|---|---|---|
| 1 | `request_context` | — | Gives it an ID and logs it, so even a refusal is findable |
| 2 | `LoadShedder` | `503` + `Retry-After` | Already too much in flight |
| 3 | `ip_rate_limit` | `429` + `Retry-After` | Too many from this address, token or not |
| 4 | `BodySizeLimit` | `413` / `400` | An oversized body, before it is read |
| 5 | `CurrentUser` | `401` / `403` / `429` / `503` | Token, per-account limit, account row, blocked |

**Cheapest first, and nothing touches the database until the end.** That order
is the whole design: a flood should be refused by a dictionary lookup, never by
something that needs a connection.

## The numbers, and how to change them

All in `app/core/config.py`, all overridable by environment variable — so they
can be tightened on a running server by changing the environment and
restarting, without a deploy.

| Setting | Default | Why that number |
|---|---|---|
| `RATE_LIMIT_PER_IP_PER_MINUTE` | 120 | Higher than the per-account limit because a phone network puts many people behind one address. Still far below what a script does |
| `RATE_LIMIT_PER_MINUTE` | 60 | Generous for a person, useless for a script |
| `MAX_IN_FLIGHT` | 50 | Well above normal concurrency, well below what exhausts memory or the pool |
| `MAX_BODY_BYTES` | 1 MB | Audio goes straight to S3; no endpoint here needs a big body |
| `DB_MAX_CONNECTIONS` | 5 | Neon's free tier has a modest budget |
| `DB_TIMEOUT_SECONDS` | 2 | Short on purpose: a long wait means requests pile up behind the pool instead of being refused |
| `SEEN_WRITE_EVERY_SECONDS` | 300 | How often `last_seen_at` is really written |

### Addresses behind a proxy

The limiter counts the address the connection came from. It does **not** read
`X-Forwarded-For`, and that is deliberate: a header is only as trustworthy as
whatever set it, so a caller who can reach the server directly would rotate the
last hop and get a fresh allowance every request. A limit that can be rotated
away is worse than none, because it looks like it is working.

Doing it properly means knowing whether *this connection* came from the proxy,
and **uvicorn already does it**:

```
uvicorn app.main:app --forwarded-allow-ips="<the proxy's address>"
```

With that, uvicorn rewrites the client address from the header for that peer
only, and the limiter reads the right thing with no code of ours to get wrong.
Without it, every request behind a proxy looks like it came from the proxy and
they all share one allowance — so this flag is not optional once something sits
in front.

## Two quieter savings

**A token that cannot be real never reaches Firebase.** A Firebase ID token is
a JWT: three dot-separated parts, about a thousand characters. Anything else is
refused by a string split, in `services/firebase_auth.py`, instead of costing
public-key crypto.

Be precise about what that buys: it only skips **obvious** rubbish. A forgery
shaped like a JWT still reaches verification and still costs a signature check.
What bounds *that* is the per-address limit — 120 verifications a minute from
one address, not unlimited. The cheap check removes the free hits; the limit
caps the expensive ones.

**`last_seen_at` is not written on every call.** Inside the rate limit one
account can call sixty times a minute, and sixty writes a minute for one
timestamp is a lot of write-ahead log. Between writes the row is **read**
instead: cheaper for Postgres, and `blocked` stays current, so cutting someone
off still takes effect on their very next call.

**Refusals are logged sparingly.** One line every five seconds per kind,
carrying how many were suppressed. A line per refused request would be work
added exactly when the point is to refuse work cheaply — and a log bill on top.

## What is deliberately *not* here

**A per-request timeout.** It sounds obvious and it would be theatre: route
handlers here are `def`, so FastAPI runs them in a worker thread, and a thread
cannot be cancelled. A timeout would return `504` to the client while the work
carried on, and worse, the in-flight count would drop while the thread was
still busy — making the shedder under-count exactly when it matters. The
deadlines that do work are the ones the work itself respects: the database
pool timeout, and `httpx` timeouts when Groq is added.

**Per-instance counting.** Both limiters count in this process's memory. Two
instances allow two windows, and a deploy resets them. That is fine for one
instance and is the first thing to change when there are two — move the
counting into Postgres or Redis.

**Anything that needs to know it is the real app.** App Check does that, and it
belongs on the list below.

## Before this is deployed

In rough order of how much they help:

1. **Put Cloudflare in front** (free). It absorbs volumetric traffic the app
   would never survive, and adds rate limiting and bot rules at the edge. This
   is worth more than everything above put together for a real flood.
2. **Start uvicorn with `--forwarded-allow-ips=<proxy>`** once that proxy
   exists — otherwise every request appears to come from the proxy and they all
   share one allowance.
3. **App Check** with Play Integrity, so requests can be tied to the real app
   rather than a script holding a stolen token.
4. **Uvicorn's own limits**: `--limit-concurrency`, `--timeout-keep-alive`,
   `--backlog`. Configuration only, no code.
5. **Move the limiters out of process** if there is ever more than one
   instance.

## If it is happening right now

1. **Look at the logs.** `carry.load` logs every shed and every rate limit, with
   the address and path. `carry.request` has one line per request with its ID.
2. **Is it one account?** Block it, and their next call gets `403`:
   ```sql
   UPDATE users SET blocked = true WHERE uid = '<the uid>';
   ```
3. **Is it one address?** Block it at the edge — Cloudflare, or the host's
   firewall. The app's limiter refuses the requests but still has to receive
   them.
4. **Is it everywhere?** Lower `RATE_LIMIT_PER_IP_PER_MINUTE` and
   `MAX_IN_FLIGHT` in the environment and restart. The server stays up serving
   fewer people, which beats being down for everyone.
5. **Is the database the problem?** A `DB_TIMEOUT_SECONDS` failure means a
   connection wasn't acquired in time. That is **not** proof the pool is
   saturated — the same timeout happens when Neon is waking from suspend, or is
   unreachable. Check connectivity first: `carry.db` logs what it couldn't do.
   Only raise `DB_MAX_CONNECTIONS` for a genuinely saturated pool, and only if
   Neon has the headroom.

## Tests

`tests/test_load.py`. Each one was checked by removing the thing it tests and
watching it fail — with the shedder and the address limit disabled, four fail
in about five seconds.

Covered: an address gets an allowance and is then refused; the limit applies to
`/health`, which has no account; it applies before a token is checked; the
socket address is used unless the proxy header can be trusted, and then the
last hop is; a request too many is shed at once and service resumes when there
is room; a token that isn't a JWT never reaches Firebase, and one that is still
does; and the `last_seen_at` throttle writes, then reads, then writes again.
