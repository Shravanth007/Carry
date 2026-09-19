# Carry

```
app/      Flutter — recorder, Drift/SQLite, sync queue, UI
server/   FastAPI — upload, Groq Whisper, notes API
```

First-time Firebase setup (both sides): see [app/docs/auth.md](app/docs/auth.md).

## App

```
cd app
flutter run
flutter test
```

## Server

```
cd server
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements-dev.txt
copy .env.example .env
fastapi dev app/main.py
pytest
```
