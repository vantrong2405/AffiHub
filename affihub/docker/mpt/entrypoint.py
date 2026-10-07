from pathlib import Path
import os
import sys

import redis
import toml


MPT_ROOT = Path("/MoneyPrinterTurbo")
CONFIG_PATH = MPT_ROOT / "config.toml"
API_KEY = os.environ.get("MPT_API_KEY", "").strip()
CALLBACK_URL = os.environ.get("MPT_TTS_FALLBACK_CALLBACK_URL", "").strip()
CALLBACK_SECRET = os.environ.get("MPT_TTS_CALLBACK_SECRET", "")
REDIS_HOST = os.environ.get("MPT_APP_REDIS_HOST", "").strip()
REDIS_PASSWORD = os.environ.get("MPT_APP_REDIS_PASSWORD", "")

if not API_KEY:
    sys.exit("MPT_API_KEY must be configured")
if not CALLBACK_URL or not CALLBACK_SECRET:
    sys.exit("MPT TTS fallback callback URL and secret must be configured")
if not REDIS_HOST:
    sys.exit("MPT_APP_REDIS_HOST must be configured for durable task state")

try:
    redis_port = int(os.environ.get("MPT_APP_REDIS_PORT", "6379"))
    redis_db = int(os.environ.get("MPT_APP_REDIS_DB", "0"))
    redis_client = redis.Redis(
        host=REDIS_HOST,
        port=redis_port,
        db=redis_db,
        password=REDIS_PASSWORD or None,
        socket_connect_timeout=5,
        socket_timeout=5,
    )
    redis_client.ping()
    redis_persistence = redis_client.info("persistence")
    if int(redis_persistence.get("aof_enabled", 0)) != 1:
        sys.exit("MPT Redis persistence requires appendonly yes")
except Exception:
    sys.exit("MPT Redis configuration is invalid or Redis is not reachable")

with (MPT_ROOT / "config.example.toml").open(encoding="utf-8") as config_file:
    configuration = toml.load(config_file)

configuration["listen_host"] = "0.0.0.0"
configuration["listen_port"] = 8080
configuration.setdefault("app", {})["api_key"] = API_KEY
configuration["chatterbox"] = {
    "base_url": os.environ.get("VIENEU_TTS_BASE_URL", "http://vieneu-tts:8000/v1"),
    "api_key": os.environ.get("VIENEU_TTS_API_KEY", ""),
    "model_id": os.environ.get("VIENEU_TTS_MODEL_ID", "vieneu-v3-turbo"),
    "response_format": "wav",
    "voices": [os.environ.get("VIENEU_TTS_VOICE", "Mai Anh")],
}
configuration.setdefault("app", {}).update(
    {
        "enable_redis": True,
        "redis_host": REDIS_HOST,
        "redis_port": redis_port,
        "redis_db": redis_db,
        "redis_password": REDIS_PASSWORD or None,
    }
)

with CONFIG_PATH.open("w", encoding="utf-8") as config_file:
    toml.dump(configuration, config_file)

os.chdir(MPT_ROOT)
os.execvp("python3", ["python3", "main.py"])
