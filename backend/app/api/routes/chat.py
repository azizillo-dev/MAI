"""Ustoz ↔ o'quvchi chat API."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Query
from pydantic import Field

from app.api.deps import DB, CurrentUser
from app.api.presenters import avatar_url
from app.models import ChatMessage, Conversation, User
from app.schemas.common import Schema
from app.services import chat

router = APIRouter(tags=["chat"])


class PeerOut(Schema):
    id: uuid.UUID
    full_name: str
    initials: str
    role: str
    avatar_url: str | None


class ConversationOut(Schema):
    id: uuid.UUID
    peer: PeerOut
    last_message_text: str | None
    last_message_at: datetime | None
    last_from_me: bool
    unread: int
    # Qarshi tomon qachon o'qigani — "o'qildi" belgisi uchun
    peer_read_at: datetime | None
    can_send: bool


class MessageOut(Schema):
    id: uuid.UUID
    text: str
    from_me: bool
    created_at: datetime


class SendIn(Schema):
    text: str = Field(min_length=1, max_length=chat.MAX_LEN)


def _initials(u: User) -> str:
    return "".join(p[0] for p in u.full_name.split() if p)[:2].upper()


def _peer(u: User) -> PeerOut:
    return PeerOut(id=u.id, full_name=u.full_name, initials=_initials(u), role=u.role, avatar_url=avatar_url(u))


def conversation_out(c: Conversation, me: User, *, can_send: bool = True) -> ConversationOut:
    is_teacher = me.id == c.teacher_id
    return ConversationOut(
        id=c.id,
        peer=_peer(c.student if is_teacher else c.teacher),
        last_message_text=c.last_message_text,
        last_message_at=c.last_message_at,
        last_from_me=c.last_sender_id == me.id,
        unread=c.teacher_unread if is_teacher else c.student_unread,
        peer_read_at=c.student_read_at if is_teacher else c.teacher_read_at,
        can_send=can_send,
    )


def message_out(m: ChatMessage, me: User) -> MessageOut:
    return MessageOut(id=m.id, text=m.text, from_me=m.sender_id == me.id, created_at=m.created_at)


@router.get("/chats", response_model=list[ConversationOut])
async def list_chats(user: CurrentUser, db: DB) -> list[ConversationOut]:
    return [conversation_out(c, user) for c in await chat.list_for(db, user)]


@router.get("/chats/unread")
async def unread(user: CurrentUser, db: DB) -> dict:
    return {"unread": await chat.unread_total(db, user)}


@router.post("/chats/with/{user_id}", response_model=ConversationOut)
async def open_chat(user_id: uuid.UUID, user: CurrentUser, db: DB) -> ConversationOut:
    c = await chat.open_with(db, user, user_id)
    return conversation_out(c, user, can_send=await chat.can_chat(db, c.teacher_id, c.student_id))


@router.get("/chats/{conv_id}", response_model=ConversationOut)
async def get_chat(conv_id: uuid.UUID, user: CurrentUser, db: DB) -> ConversationOut:
    c = await chat.get_own(db, user, conv_id)
    return conversation_out(c, user, can_send=await chat.can_chat(db, c.teacher_id, c.student_id))


@router.get("/chats/{conv_id}/messages", response_model=list[MessageOut])
async def get_messages(
    conv_id: uuid.UUID,
    user: CurrentUser,
    db: DB,
    after: datetime | None = Query(None, description="Shu vaqtdan keyingi yangi xabarlar"),
    before: datetime | None = Query(None, description="Shu vaqtdan oldingi eski xabarlar"),
) -> list[MessageOut]:
    c = await chat.get_own(db, user, conv_id)
    return [message_out(m, user) for m in await chat.messages(db, c, after=after, before=before)]


@router.post("/chats/{conv_id}/messages", response_model=MessageOut, status_code=201)
async def send_message(conv_id: uuid.UUID, body: SendIn, user: CurrentUser, db: DB) -> MessageOut:
    c = await chat.get_own(db, user, conv_id)
    return message_out(await chat.send(db, user, c, body.text), user)


@router.post("/chats/{conv_id}/read", status_code=204)
async def read(conv_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    c = await chat.get_own(db, user, conv_id)
    await chat.mark_read(db, user, c)
