"""Yordam va taklif, o'qituvchi jetonlari, taqdimot sayti uchun ochiq API."""

import uuid
from typing import Literal

from fastapi import APIRouter, Response
from pydantic import Field
from sqlalchemy import select

from app.api.deps import DB, CurrentTeacher, CurrentUser
from app.models import JetonOrder, SupportMessage
from app.schemas.common import Schema
from app.services import jetons, site

router = APIRouter(tags=["extras"])


# ---------------------------------------------------------------- Yordam va taklif


class SupportIn(Schema):
    kind: Literal["help", "suggestion", "bug"] = "help"
    text: str = Field(min_length=5, max_length=3000)


def support_out(m: SupportMessage) -> dict:
    return {"id": m.id, "kind": m.kind, "text": m.text, "status": m.status, "admin_reply": m.admin_reply,
            "replied_at": m.replied_at, "created_at": m.created_at}


@router.post("/support", status_code=201)
async def send_support(body: SupportIn, user: CurrentUser, db: DB) -> dict:
    m = SupportMessage(user_id=user.id, kind=body.kind, text=body.text.strip())
    db.add(m)
    await db.commit()
    await db.refresh(m)
    return support_out(m)


@router.get("/support")
async def my_support(user: CurrentUser, db: DB) -> list[dict]:
    rows = await db.scalars(
        select(SupportMessage).where(SupportMessage.user_id == user.id)
        .order_by(SupportMessage.created_at.desc()).limit(50)
    )
    return [support_out(m) for m in rows]


# ---------------------------------------------------------------- O'qituvchi jetonlari


def order_out(o: JetonOrder) -> dict:
    return {"id": o.id, "jeton_code": o.jeton_code, "quantity": o.quantity, "amount_uzs": o.amount_uzs,
            "status": o.status, "admin_note": o.admin_note, "created_at": o.created_at, "decided_at": o.decided_at}


@router.get("/teachers/jetons")
async def my_jetons(teacher: CurrentTeacher, db: DB) -> dict:
    """Katalog, qo'limdagi jetonlar, buyurtmalar va nechta sovg'a qilinganligi."""
    orders = await db.scalars(
        select(JetonOrder).where(JetonOrder.teacher_id == teacher.id).order_by(JetonOrder.created_at.desc()).limit(20)
    )
    return {
        "catalog": [jetons.jeton_dict(j) for j in await jetons.catalog(db)],
        "balances": await jetons.balances(db, teacher.id),
        "orders": [order_out(o) for o in orders],
        "given": await jetons.given_count(db, teacher.id),
    }


class JetonOrderIn(Schema):
    jeton_code: str = Field(max_length=40)
    quantity: int = Field(ge=1, le=500)
    note: str | None = Field(default=None, max_length=500)


@router.post("/teachers/me/jeton-orders", status_code=201)
async def order_jetons(body: JetonOrderIn, teacher: CurrentTeacher, db: DB) -> dict:
    return order_out(await jetons.create_order(db, teacher, body.jeton_code, body.quantity, body.note))


class GiftIn(Schema):
    student_id: uuid.UUID
    jeton_code: str = Field(max_length=40)
    note: str | None = Field(default=None, max_length=200)


@router.post("/teachers/me/jetons/gift", status_code=201)
async def gift_jeton(body: GiftIn, teacher: CurrentTeacher, db: DB) -> dict:
    award = await jetons.gift(db, teacher, body.student_id, body.jeton_code, body.note)
    return {"id": award.id, "jeton_code": award.badge_code, "awarded_at": award.awarded_at,
            "balances": await jetons.balances(db, teacher.id)}


# ---------------------------------------------------------------- Taqdimot sayti (ochiq)


@router.get("/site/public")
async def site_public(db: DB) -> dict:
    return await site.public_info(db)


@router.get("/site/founders/{fid}/photo", include_in_schema=False)
async def founder_photo(fid: str, db: DB) -> Response:
    # Havolada rasm versiyasi (?v=) bor — rasm almashsa havola ham o'zgaradi, shuning uchun uzoq keshlaymiz
    return Response(await site.founder_photo(db, fid), media_type="image/jpeg",
                    headers={"Cache-Control": "public, max-age=31536000, immutable"})


class SecretIn(Schema):
    password: str = Field(min_length=1, max_length=200)


@router.post("/site/secret")
async def site_secret(body: SecretIn, db: DB) -> dict:
    return await site.open_secret(db, body.password)
