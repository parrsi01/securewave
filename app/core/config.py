import os
from dotenv import load_dotenv

load_dotenv()

PROJECT_NAME = os.getenv("PROJECT_NAME", "CloudSecure Backend")
API_PREFIX = os.getenv("API_PREFIX", "/api")

DB_URL = os.getenv("DB_URL", "sqlite:///./cloudsecure.db")

JWT_SECRET = os.getenv("JWT_SECRET", "change-me")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))
REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "30"))

WG_ENDPOINT = os.getenv("WG_ENDPOINT", "vpn.example.com:51820")
WG_DNS = os.getenv("WG_DNS", "1.1.1.1")
WG_ALLOWED_IPS = os.getenv("WG_ALLOWED_IPS", "0.0.0.0/0, ::/0")
WG_PERSISTENT_KEEPALIVE = os.getenv("WG_PERSISTENT_KEEPALIVE", "25")
WG_SERVER_PUBLIC_KEY = os.getenv("WG_SERVER_PUBLIC_KEY", "")

DEVICE_TOKEN_BYTES = int(os.getenv("DEVICE_TOKEN_BYTES", "32"))
