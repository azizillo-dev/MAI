import uuid
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import Forbidden, Unauthorized
from app.core.security import as_utc, decode_access_token, utcnow
from app.db.session import get_db
from app.models import AuthSession, Role, User

DB = Annotated[AsyncSession, Depends(get_db)]

_bearer = HTTPBearer(auto_error=False)


class Principal:
    def __init__(self, user: User, session_id: uuid.UUID) -> None:
        self.user = user
        self.session_id = session_id


async def get_principal(
    db: DB, creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)]
) -> Principal:
    if creds is None:
        raise Unauthorized("AUTH_REQUIRED", "Tizimga kiring")
    payload = decode_access_token(creds.credentials)
    # Har bir so'rovda ishlaydi: sessiya va foydalanuvchi (profili bilan) bitta so'rovda olinadi
    row = (await db.execute(
        select(AuthSession, User)
        .join(User, User.id == AuthSession.user_id)
        .where(AuthSession.id == uuid.UUID(payload["sid"]), User.id == uuid.UUID(payload["sub"]))
    )).first()
    session, user = row if row else (None, None)
    # Chiqib ketilgan (logout) sessiya access token muddati tugashini kutmasdan darhol yopiladi
    if session is None or session.revoked_at is not None or as_utc(session.expires_at) < utcnow():
        raise Unauthorized("SESSION_INVALID", "Sessiya tugagan. Qaytadan kiring")
    if not user.is_active:
        raise Unauthorized("USER_BLOCKED", "Akkaunt bloklangan")
    return Principal(user, session.id)


CurrentPrincipal = Annotated[Principal, Depends(get_principal)]


async def get_user(p: CurrentPrincipal) -> User:
    return p.user


async def get_teacher(p: CurrentPrincipal) -> User:
    if p.user.role != Role.TEACHER:
        raise Forbidden("ROLE_FORBIDDEN", "Bu bo'lim faqat o'qituvchilar uchun")
    return p.user


async def get_student(p: CurrentPrincipal) -> User:
    if p.user.role != Role.STUDENT:
        raise Forbidden("ROLE_FORBIDDEN", "Bu bo'lim faqat o'quvchilar uchun")
    return p.user


CurrentUser = Annotated[User, Depends(get_user)]
CurrentTeacher = Annotated[User, Depends(get_teacher)]
CurrentStudent = Annotated[User, Depends(get_student)]


def client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None
