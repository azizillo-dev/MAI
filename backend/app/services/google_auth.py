"""Google orqali kirish: ilova Google'dan olgan ID token'ni tekshiramiz.

Token imzosi Google'ning ochiq kalitlari (JWKS) bilan tekshiriladi, `aud` — bizning client ID'lardan
biri (GOOGLE_CLIENT_IDS, vergul bilan), `iss` — Google, email tasdiqlangan bo'lishi shart.
"""

import asyncio
from dataclasses import dataclass

import jwt
from jwt import PyJWKClient

from app.core.config import get_settings
from app.core.errors import AppError, Unauthorized

_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
_jwks: PyJWKClient | None = None


@dataclass
class GoogleIdentity:
    email: str
    first_name: str | None
    last_name: str | None


def client_ids() -> list[str]:
    return [c.strip() for c in get_settings().google_client_ids.split(",") if c.strip()]


def _decode(token: str, audience: list[str]) -> dict:
    global _jwks
    if _jwks is None:
        _jwks = PyJWKClient("https://www.googleapis.com/oauth2/v3/certs", cache_keys=True, lifespan=3600)
    key = _jwks.get_signing_key_from_jwt(token).key
    return jwt.decode(token, key, algorithms=["RS256"], audience=audience, issuer=_ISSUERS, leeway=30)


async def verify_id_token(token: str) -> GoogleIdentity:
    audience = client_ids()
    if not audience:
        raise AppError("GOOGLE_NOT_CONFIGURED", "Google orqali kirish hali sozlanmagan. Email orqali kiring", 503)
    try:
        # Kalitlarni yuklash tarmoq so'rovi — server boshqa so'rovlarni kutib qolmasin
        claims = await asyncio.to_thread(_decode, token, audience)
    except jwt.PyJWKClientError as exc:
        raise AppError("GOOGLE_UNAVAILABLE", "Google bilan bog'lanib bo'lmadi. Birozdan keyin urinib ko'ring", 503) from exc
    except jwt.InvalidTokenError as exc:
        raise Unauthorized("GOOGLE_TOKEN_INVALID", "Google orqali kirish tasdiqlanmadi. Qayta urinib ko'ring") from exc
    email = (claims.get("email") or "").strip().lower()
    if not email or not claims.get("email_verified"):
        raise Unauthorized("GOOGLE_EMAIL_UNVERIFIED", "Google akkauntingizdagi email tasdiqlanmagan")
    return GoogleIdentity(email=email, first_name=claims.get("given_name"), last_name=claims.get("family_name"))
