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
DB_TIMEOUT_SECONDS = float(os.getenv("DB_TIMEOUT_SECONDS", "10"))

# Calls per minute per account. Generous for a person, useless for a script.
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))

# Audio never comes through here: it goes straight to S3 with a signed URL.
# 1 MB is far more than any JSON this API accepts.
MAX_BODY_BYTES = int(os.getenv("MAX_BODY_BYTES", str(1024 * 1024)))
