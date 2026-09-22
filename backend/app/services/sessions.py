from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import Unauthorized
from app.core.security import as_utc, create_access_token, hash_token, new_refresh_token, utcnow
from app.models import AuthSession, User


@dataclass
class TokenPair:
    access_token: str
    refresh_token: str
    expires_in: int


async def open_session(db: AsyncSession, user: User, device_name: str | None, ip: str | None) -> TokenPair:
    s = get_settings()
    now = utcnow()
    refresh = new_refresh_token()
    session = AuthSession(
        user_id=user.id,
        refresh_token_hash=hash_token(refresh),
        device_name=(device_name or "")[:128] or None,
        ip=ip,
        created_at=now,
        last_used_at=now,
        expires_at=now + timedelta(days=s.refresh_token_days),
    )
    db.add(session)
    user.last_login_at = now
    await db.flush()
    return TokenPair(create_access_token(user.id, user.role, session.id), refresh, s.access_token_minutes * 60)


async def rotate_session(db: AsyncSession, refresh_token: str) -> TokenPair:
    s = get_settings()
    now = utcnow()
    token_hash = hash_token(refresh_token)

    session = await db.scalar(
        select(AuthSession).where(AuthSession.refresh_token_hash == token_hash).with_for_update()
    )
    if session is None:
        # Eski (allaqachon almashtirilgan) token qayta ishlatildi: token o'g'irlangan bo'lishi mumkin.
        stolen = await db.scalar(select(AuthSession).where(AuthSession.previous_token_hash == token_hash))
        if stolen is not None and stolen.revoked_at is None:
            stolen.revoked_at = now
            await db.commit()
        raise Unauthorized("SESSION_INVALID", "Sessiya tugagan. Qaytadan kiring")

    if session.revoked_at is not None or as_utc(session.expires_at) < now:
        raise Unauthorized("SESSION_INVALID", "Sessiya tugagan. Qaytadan kiring")

    user = await db.get(User, session.user_id)
    if user is None or not user.is_active:
        raise Unauthorized("USER_BLOCKED", "Akkaunt bloklangan")

    new_refresh = new_refresh_token()
    session.previous_token_hash = token_hash
    session.refresh_token_hash = hash_token(new_refresh)
    session.last_used_at = now
    session.expires_at = now + timedelta(days=s.refresh_token_days)
    await db.commit()
    return TokenPair(create_access_token(user.id, user.role, session.id), new_refresh, s.access_token_minutes * 60)


async def revoke_session(db: AsyncSession, session_id) -> None:
    await db.execute(
        update(AuthSession)
        .where(AuthSession.id == session_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )
    await db.commit()
