# CLAUDE.md — Carry server

Guidance for Claude Code when working on the Carry backend.

## What this is

This is the API behind the Carry voice notes app. The app uploads audio, the
server transcribes it with Groq Whisper, and it serves the notes back. The
Flutter app lives in `../app` and has its own CLAUDE.md.

**Stack:** Python 3.13, FastAPI, and Firebase Admin (sign-in checks).
**Today:** `/health` (open), `/me` (signed in) and `/billing/webhook` (the
store's). Plans and quotas exist; nothing meters them yet.
**Planned:** audio upload, transcription and a notes API.

## Docs

| Working on... | Read |
|---|---|
| Auth: how tokens are checked, the service account key, error responses | [../app/docs/auth.md](../app/docs/auth.md) |
| Trust model, limits, quotas, presigned uploads, secrets | [docs/security.md](docs/security.md) |
| Staying up under a flood: what refuses what, in which order | [docs/load.md](docs/load.md) |
| Plans, quotas, entitlements, and what the webhook may do | [../app/docs/payments.md](../app/docs/payments.md) |

## Structure

Everything lives in the `app` package. Each layer has one job:

| Folder | Holds | Rule |
|---|---|---|
| `main.py` | Creates the FastAPI app and wires middleware and routers | No logic |
| `core/` | Settings (env vars, `.env` loading) | Read env vars here, not across the code |
| `routes/` | One router per feature (`health`, `users`, later `notes`, `uploads`) | Thin: parse input, call a service, return a schema |
| `services/` | Business logic and outside systems (Firebase, later Groq, storage) | No FastAPI imports |
| `dependencies/` | `Depends(...)` providers, e.g. `CurrentUser` | Where tests swap things out |
| `schemas/` | Pydantic request and response models | Every route returns one |
| `middleware/` | Per-request concerns: request ID and access log | Never log headers or bodies |
| `utils/` | Small helpers with no app knowledge (logging setup) | No imports from other app layers |

`tests/` has one file per feature. `conftest.py` provides the `client`
fixture, and `helpers.py` holds shared test values.

To add a feature:
1. Add a schema.
2. Add a service.
3. Add a router in `routes/`.
4. Register it in `main.py`.
5. Add tests.

## Commands

```
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements-dev.txt
copy .env.example .env           # then point it at the service account key
fastapi dev app/main.py          # auto-reloads on save
pytest
```

CI (`.github/workflows/ci.yml`) runs `pytest` on every push to a PR. A
server-only PR skips the Flutter jobs entirely, so it finishes in about half
a minute.

`main` is protected: no direct pushes. Open a PR and merge once the **All
checks** gate is green.

## Rules

- **Auth:** every endpoint except `/health` takes `user: CurrentUser` and uses
  `user.uid`. Never trust a user ID sent in the request body, a header or a
  path. The app is a public repo: anyone can write their own client, so every
  limit is enforced here, never in Flutter. See [docs/security.md](docs/security.md).
- **Cheapest check first.** A request meets the load shedder, then the
  per-address limit, then the body cap, and only then anything that needs the
  database. A flood must be refused by a dictionary lookup, never by something
  that takes a connection. See [docs/load.md](docs/load.md).
- **Quotas before creation:** check an account's allowance before creating a
  row or signing an upload URL. A signed URL is storage already spent.
  `usage.check()` is the call, and it belongs before the spending, never after.
- **Money:** nothing here can charge anyone - Google takes the money and
  RevenueCat reports it. What a bug in `billing.py` *can* do is give away
  access or take away access someone paid for, so: only a verified event
  changes a plan, every event applies at most once, arrival order means
  nothing (the period does), and a refund is immediate.
- **Secrets:** the service account key and Groq keys are read from environment
  variables or `.env`. `.env` and `secrets/` are git-ignored, and secrets never
  go in code.
- **Validation:** check uploads at the edge: file type, size limit, and empty files.
- **Errors:** return clear HTTP status codes with a short `detail` message the app
  can act on.
- **Request IDs:** every response carries `X-Request-ID`. Include it when
  reporting a server problem.
- **Packages:** don't add one for something a few lines can do. Pin versions in
  `requirements.txt`, and put test-only packages in `requirements-dev.txt`.
- **Calling Groq:** use `httpx`, not `urllib`. Groq sits behind Cloudflare,
  which rejects `Python-urllib`'s user agent with a 403 (error 1010) before
  the request reaches Groq, so a working key looks like a rejected one. `httpx`
  arrives transitively through `firebase-admin` today: pin it in
  `requirements.txt` when the transcription service starts importing it.

## Testing

- Use `pytest` with the `client` fixture.
- Tests never call real Firebase or Groq. Swap them out with
  `app.dependency_overrides`. The `client` fixture already swaps
  `token_verifier`, so the token `"valid-token"` signs in as `TEST_USER`.
- Cover:
  - success,
  - a missing, invalid or expired token,
  - bad input (wrong type, too large, empty),
  - upstream failure (timeout or error).

## Before raising a PR: review your own diff

`pytest` passing is not a review. Tests written alongside the code share its
assumptions. **Read `git diff main...HEAD` top to bottom before opening the
PR**, and look for what a test can't see:

1. **Check each change against the rules above** and against
   [docs/security.md](docs/security.md). Breaking a rule from the same PR is the
   easiest mistake to make.
2. **Order of checks.** A cheap check after an expensive one protects nothing:
   the limit goes before the database, not after it.
3. **Anything shared between requests** — a module-level dict, a counter, a
   pool. FastAPI runs a `def` dependency in a worker thread, so two requests
   really are inside it at once.
4. **Follow every value that leaves the process** — a response, a log line, an
   event. A uid, a status and a request id are fine; a token, an email or an
   exception's text are not.
5. **Every error path has a status code you chose.** Anything that can raise
   and isn't caught becomes a 500 that says nothing.
6. **Then run it:** `pytest`, and read the failures.

## Planning

For non-trivial work:
1. List the edge cases first: duplicate uploads, retries from the app's sync
   queue, large files, timeouts, and auth expiring.
2. Play the plan back to the user and get an OK before coding.

## Git

- Commit format: `type(server): description`.
  - `type` is one of feat, fix, docs, refactor, test, chore.
  - Imperative mood, subject under 50 characters.
- **No Claude co-author lines and no Claude session links in commits or PRs.**

Keep this file current when you add endpoints, folders, docs, commands or rules.
