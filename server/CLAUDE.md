# CLAUDE.md — Carry server

Guidance for Claude Code when working on the Carry backend.

## What this is

This is the API behind the Carry voice notes app. The app uploads audio, the
server transcribes it with Groq Whisper, and it serves the notes back. The
Flutter app lives in `../app` and has its own CLAUDE.md.

**Stack:** Python 3.13, FastAPI, and Firebase Admin (sign-in checks).
**Today:** `/health` (open) and `/me` (signed in).
**Planned:** audio upload, transcription and a notes API.

## Docs

| Working on... | Read |
|---|---|
| Auth: how tokens are checked, the service account key, error responses | [../app/docs/auth.md](../app/docs/auth.md) |

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

## Rules

- **Auth:** every endpoint except `/health` takes `user: CurrentUser` and uses
  `user["uid"]`. Never trust a user ID sent in the request body.
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
