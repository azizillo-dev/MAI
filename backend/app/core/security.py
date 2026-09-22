import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt

from app.core.config import get_settings
from app.core.errors import Unauthorized

ACCESS = "access"
REGISTRATION = "registration"


def utcnow() -> datetime:
    return datetime.now(UTC)


def as_utc(value: datetime) -> datetime:
    """SQLite vaqt zonasini saqlamaydi; solishtirishdan oldin UTC deb belgilaymiz."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def _encode(payload: dict[str, Any], ttl: timedelta) -> str:
    s = get_settings()
    now = utcnow()
    payload = {**payload, "iat": int(now.timestamp()), "exp": int((now + ttl).timestamp())}
    return jwt.encode(payload, s.jwt_secret, algorithm=s.jwt_algorithm)


def _decode(token: str, expected_type: str) -> dict[str, Any]:
    s = get_settings()
    try:
        payload = jwt.decode(token, s.jwt_secret, algorithms=[s.jwt_algorithm])
    except jwt.ExpiredSignatureError as exc:
        raise Unauthorized("TOKEN_EXPIRED", "Sessiya muddati tugadi") from exc
    except jwt.InvalidTokenError as exc:
        raise Unauthorized("TOKEN_INVALID", "Avtorizatsiya xatosi") from exc
    if payload.get("typ") != expected_type:
        raise Unauthorized("TOKEN_INVALID", "Avtorizatsiya xatosi")
    return payload


def create_access_token(user_id: uuid.UUID, role: str, session_id: uuid.UUID) -> str:
    s = get_settings()
    return _encode(
        {"sub": str(user_id), "role": role, "sid": str(session_id), "typ": ACCESS},
        timedelta(minutes=s.access_token_minutes),
    )


def decode_access_token(token: str) -> dict[str, Any]:
    return _decode(token, ACCESS)


def create_registration_token(*, phone: str | None = None, email: str | None = None) -> str:
    """Telefon yoki email egaligi tasdiqlangani haqidagi qisqa muddatli guvohnoma."""
    s = get_settings()
    return _encode({"phone": phone, "email": email, "typ": REGISTRATION}, timedelta(minutes=s.registration_token_minutes))


def decode_registration_token(token: str) -> tuple[str | None, str | None]:
    """(telefon, email) qaytaradi — bittasi to'ldirilgan bo'ladi."""
    try:
        payload = _decode(token, REGISTRATION)
    except Unauthorized as exc:
        raise Unauthorized(
            "REGISTRATION_EXPIRED", "Ro'yxatdan o'tish vaqti tugadi. Qaytadan tasdiqlang"
        ) from exc
    return payload.get("phone"), payload.get("email")


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return f"scrypt${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str | None) -> bool:
    if not stored or not stored.startswith("scrypt$"):
        return False
    _, salt_hex, digest_hex = stored.split("$")
    digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt_hex), n=2**14, r=8, p=1)
    return hmac.compare_digest(digest.hex(), digest_hex)


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def generate_otp(length: int) -> str:
    return "".join(secrets.choice("0123456789") for _ in range(length))


def hash_otp(phone: str, code: str) -> str:
    key = get_settings().otp_secret.encode()
    return hmac.new(key, f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def otp_matches(phone: str, code: str, code_hash: str) -> bool:
    return hmac.compare_digest(hash_otp(phone, code), code_hash)
