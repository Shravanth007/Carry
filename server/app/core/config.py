"""Settings from environment variables, with `.env` loaded first.

Firebase reads GOOGLE_APPLICATION_CREDENTIALS itself, so it isn't listed here.
"""

import os

from dotenv import load_dotenv

load_dotenv()

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
