"""Ustoz ↔ o'quvchi yozishmasi.

Qoidalar:
* Ustoz faqat o'z guruhlaridan birining faol a'zosi bo'lgan o'quvchiga yoza oladi; o'quvchi — faqat
  o'z ustoziga. A'zolik tugasa, eski yozishma o'qiladi, lekin yangi xabar yuborib bo'lmaydi.
* Yangi xabarlar so'rov bilan olinadi (ochiq chat bir necha soniyada so'raydi) — server 2 jarayonda,
  WebSocket'siz ham ishonchli ishlaydi.
"""

import uuid
from datetime import datetime, timedelta

from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Forbidden, NotFound
from app.core.security import utcnow
from app.models import ChatMessage, Conversation, Group, GroupMember, GroupStatus, MemberStatus, Role, User

MAX_LEN = 2000
PER_MINUTE = 20
PAGE = 50


async def can_chat(db: AsyncSession, teacher_id: uuid.UUID, student_id: uuid.UUID) -> bool:
    found = await db.scalar(
        select(GroupMember.id)
        .join(Group, Group.id == GroupMember.group_id)
        .where(
            Group.teacher_id == teacher_id,
            Group.status == GroupStatus.ACTIVE,
            GroupMember.student_id == student_id,
            GroupMember.status == MemberStatus.ACTIVE,
        )
        .limit(1)
    )
    return found is not None


def _pair(me: User, other_id: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    """(teacher_id, student_id) — kim kimga yozayotganidan qat'i nazar."""
    return (me.id, other_id) if me.role == Role.TEACHER else (other_id, me.id)


async def open_with(db: AsyncSession, me: User, other_id: uuid.UUID) -> Conversation:
    """Suhbatni topadi yoki ochadi (ruxsat tekshiriladi)."""
    if me.role not in (Role.TEACHER, Role.STUDENT) or other_id == me.id:
        raise Forbidden("CHAT_FORBIDDEN", "Bu foydalanuvchiga yozib bo'lmaydi")
    teacher_id, student_id = _pair(me, other_id)
    conv = await db.scalar(
        select(Conversation).where(Conversation.teacher_id == teacher_id, Conversation.student_id == student_id)
    )
    if conv is not None:
        return conv
    if not await can_chat(db, teacher_id, student_id):
        raise Forbidden("CHAT_FORBIDDEN", "Faqat o'z guruhingizdagi o'quvchi va ustoz bilan yozishish mumkin")
    conv = Conversation(teacher_id=teacher_id, student_id=student_id)
    db.add(conv)
    await db.commit()
    await db.refresh(conv)
    return conv


async def get_own(db: AsyncSession, me: User, conv_id: uuid.UUID) -> Conversation:
    conv = await db.get(Conversation, conv_id)
    if conv is None or me.id not in (conv.teacher_id, conv.student_id):
        raise NotFound("CHAT_NOT_FOUND", "Suhbat topilmadi")
    return conv


async def list_for(db: AsyncSession, me: User) -> list[Conversation]:
    rows = await db.scalars(
        select(Conversation)
        .where(or_(Conversation.teacher_id == me.id, Conversation.student_id == me.id))
        .where(Conversation.last_message_at.is_not(None))
        .order_by(Conversation.last_message_at.desc())
        .limit(200)
    )
    return list(rows)


async def unread_total(db: AsyncSession, me: User) -> int:
    col = Conversation.teacher_unread if me.role == Role.TEACHER else Conversation.student_unread
    own = Conversation.teacher_id if me.role == Role.TEACHER else Conversation.student_id
    return int(await db.scalar(select(func.coalesce(func.sum(col), 0)).where(own == me.id)) or 0)


async def messages(
    db: AsyncSession, conv: Conversation, *, after: datetime | None = None, before: datetime | None = None
) -> list[ChatMessage]:
    q = select(ChatMessage).where(ChatMessage.conversation_id == conv.id)
    if after is not None:
        # Yangi xabarlar (so'rov bilan kuzatish): eskidan yangiga
        rows = await db.scalars(q.where(ChatMessage.created_at > after).order_by(ChatMessage.created_at).limit(PAGE))
        return list(rows)
    if before is not None:
        q = q.where(ChatMessage.created_at < before)
    rows = list(await db.scalars(q.order_by(ChatMessage.created_at.desc()).limit(PAGE)))
    return rows[::-1]


async def send(db: AsyncSession, me: User, conv: Conversation, text: str) -> ChatMessage:
    text = text.strip()
    if not text:
        raise AppError("MESSAGE_EMPTY", "Xabar bo'sh", 422)
    if len(text) > MAX_LEN:
        raise AppError("MESSAGE_TOO_LONG", f"Xabar {MAX_LEN} belgidan oshmasin", 422)
    if not await can_chat(db, conv.teacher_id, conv.student_id):
        raise Forbidden("CHAT_CLOSED", "O'quvchi endi guruhda emas — yangi xabar yuborib bo'lmaydi")
    now = utcnow()
    recent = await db.scalar(
        select(func.count()).select_from(ChatMessage).where(
            ChatMessage.sender_id == me.id, ChatMessage.created_at >= now - timedelta(minutes=1)
        )
    )
    if (recent or 0) >= PER_MINUTE:
        raise AppError("MESSAGE_RATE", "Juda tez yozyapsiz. Birozdan keyin davom eting", 429)

    msg = ChatMessage(conversation_id=conv.id, sender_id=me.id, text=text, created_at=now)
    db.add(msg)
    is_teacher = me.id == conv.teacher_id
    # Sanoq bazaning o'zida oshiriladi — ikki jarayon bir vaqtda yozsa ham to'g'ri chiqadi
    await db.execute(
        update(Conversation)
        .where(Conversation.id == conv.id)
        .values(
            last_message_at=now,
            last_message_text=text[:200],
            last_sender_id=me.id,
            **({"student_unread": Conversation.student_unread + 1} if is_teacher else
               {"teacher_unread": Conversation.teacher_unread + 1}),
            # O'zi yozgan suhbatni o'qigan hisoblanadi
            **({"teacher_unread": 0, "teacher_read_at": now} if is_teacher else
               {"student_unread": 0, "student_read_at": now}),
        )
    )
    await db.commit()
    await db.refresh(msg)
    return msg


async def mark_read(db: AsyncSession, me: User, conv: Conversation) -> None:
    now = utcnow()
    values = (
        {"teacher_unread": 0, "teacher_read_at": now}
        if me.id == conv.teacher_id
        else {"student_unread": 0, "student_read_at": now}
    )
    await db.execute(update(Conversation).where(Conversation.id == conv.id).values(**values))
    await db.commit()
