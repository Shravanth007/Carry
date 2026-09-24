"""Settings from environment variables, with `.env` loaded first.

Firebase reads GOOGLE_APPLICATION_CREDENTIALS itself, so it isn't listed here.
Limits live here rather than in the app: the app can be modified, this cannot.
"""

import os

from dotenv import load_dotenv

load_dotenv()

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Neon connection string. Empty means anything needing the database answers 503.
DATABASE_URL = os.getenv("DATABASE_URL", "")
DB_MAX_CONNECTIONS = int(os.getenv("DB_MAX_CONNECTIONS", "5"))
# Short on purpose: a long wait for a connection means requests pile up behind
# the pool under load instead of being refused quickly.
DB_TIMEOUT_SECONDS = float(os.getenv("DB_TIMEOUT_SECONDS", "2"))

# Calls per minute per account. Generous for a person, useless for a script.
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))

# Calls per minute from one address, signed in or not. Higher than the
# per-account limit because a phone network puts many people behind one address,
# and this is the only limit that applies before a token is checked.
RATE_LIMIT_PER_IP_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_IP_PER_MINUTE", "120"))

# How many requests may be in flight before new ones are refused. Refusing is
# better than queueing: a queue holds memory and workers until nothing finishes.
MAX_IN_FLIGHT = int(os.getenv("MAX_IN_FLIGHT", "50"))

# How often an account's last_seen_at is actually written. Between writes the
# row is read instead, which costs Postgres far less and keeps blocking
# immediate.
SEEN_WRITE_EVERY_SECONDS = float(os.getenv("SEEN_WRITE_EVERY_SECONDS", "300"))

# Audio never comes through here: it goes straight to S3 with a signed URL.
# 1 MB is far more than any JSON this API accepts.
MAX_BODY_BYTES = int(os.getenv("MAX_BODY_BYTES", str(1024 * 1024)))
