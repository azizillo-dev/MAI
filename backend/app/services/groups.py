"""Guruhlar va o'quvchining guruhga qo'shilishi.

Qo'shilish usullari (o'qituvchi ma'lumotni qanday beradi):
  1. Kod + parol:  "K7M4-XQ9P" va "4829 1375" — doskaga yozish yoki og'zaki aytish uchun.
  2. QR kod:       sinfda ekranni ko'rsatadi, o'quvchi skaner qiladi (parol shart emas).
  3. Havola:       Telegram guruhiga "Ulashish" orqali tashlanadi (parol shart emas).

Qoidalar:
  - Qaysi usulda bo'lmasin, o'quvchi "pending" holatiga tushadi: ustoz TASDIQLAMAGUNCHA guruhga kirmaydi.
    Kod/parol begona odamga tarqalib ketsa ham, u guruhga o'zi kira olmaydi.
  - Ustoz hamma qo'shilib bo'lgach qo'shilishni yopadi (join_enabled=False) — kod, QR va havola ishlamaydi.
    Keyin yangi o'quvchi kerak bo'lsa qayta ochadi.
  - Kod ham, parol ham 8 belgili va butun tizimda yagona (DB'da UNIQUE).
  - Parol yangilanganda QR/havola tokeni ham almashadi, eski havolalar ishlamay qoladi.
"""

import secrets
import uuid
from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import AppError, Conflict, Forbidden, NotFound, TooManyRequests
from app.core.security import utcnow
from app.models import Group, GroupMember, GroupStatus, JoinAttempt, MemberStatus, User
from app.services import plans

CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # 0/O, 1/I/L yo'q
CODE_LENGTH = 8
PASSWORD_LENGTH = 8


def normalize_code(raw: str) -> str:
    """"k7m4-xq9p", "K7M4 XQ9P" -> "K7M4XQ9P"."""
    return "".join(ch for ch in (raw or "").upper() if ch.isalnum())


def normalize_password(raw: str) -> str:
    """"4829 1375" -> "48291375"."""
    return "".join(ch for ch in (raw or "") if ch.isdigit())


def format_code(code: str) -> str:
    return f"{code[:4]}-{code[4:]}" if len(code) == CODE_LENGTH else code


def _new_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def _new_password() -> str:
    # Birinchi raqam 0 bo'lmaydi: Excel/telefon kontaktlarida "0" tushib qolmasin
    return str(secrets.randbelow(9) + 1) + "".join(secrets.choice("0123456789") for _ in range(PASSWORD_LENGTH - 1))


def _new_invite_token() -> str:
    return secrets.token_urlsafe(16)[:22]


def invite_url(group: Group) -> str:
    return f"{get_settings().public_join_url}/{group.join_code}?t={group.invite_token}"


async def _unique(db: AsyncSession, column, generate) -> str:
    """Bazada yo'q qiymat topilguncha generatsiya qiladi. UNIQUE cheklov poyga holatidan ham himoya qiladi."""
    for _ in range(20):
        value = generate()
        if not await db.scalar(select(Group.id).where(column == value)):
            return value
    raise RuntimeError("Yagona qiymat yaratib bo'lmadi")


async def _commit_unique(db: AsyncSession, group: Group, *, new_code: bool) -> None:
    """Juda kam holatda ikki so'rov bir vaqtda bir xil kod/parol olsa, qayta generatsiya qilib saqlaydi.

    [new_code]=False (parolni yangilash): mavjud guruhning kodi hech qachon o'zgarmaydi.
    """
    for attempt in range(3):
        try:
            await db.commit()
            return
        except IntegrityError:
            await db.rollback()
            if attempt == 2:
                raise
            if new_code:
                group.join_code = await _unique(db, Group.join_code, _new_code)
            group.join_password = await _unique(db, Group.join_password, _new_password)
            group.invite_token = _new_invite_token()
            db.add(group)


async def create_group(db: AsyncSession, teacher: User, name: str, subject: str, grading_scale: str | None) -> Group:
    plan = await plans.require_plan(db, teacher.id)
    if await plans.active_group_count(db, teacher.id) >= plan.max_groups:
        raise Forbidden(
            "PLAN_GROUP_LIMIT",
            f"{plan.name} tarifida {plan.max_groups} ta guruh ochish mumkin. Ko'proq guruh uchun tarifni yangilang",
            details={"limit": plan.max_groups, "plan": plan.code},
        )
    group = Group(
        teacher_id=teacher.id,
        name=name,
        subject=subject,
        grading_scale=grading_scale or (teacher.teacher.default_grading_scale if teacher.teacher else "5"),
        join_code=await _unique(db, Group.join_code, _new_code),
        join_password=await _unique(db, Group.join_password, _new_password),
        invite_token=_new_invite_token(),
        join_enabled=True,
    )
    db.add(group)
    await _commit_unique(db, group, new_code=True)
    await db.refresh(group)
    return group


async def get_teacher_group(db: AsyncSession, teacher: User, group_id: uuid.UUID) -> Group:
    group = await db.get(Group, group_id)
    if group is None or group.teacher_id != teacher.id:
        raise NotFound("GROUP_NOT_FOUND", "Guruh topilmadi")
    return group


async def rotate_credentials(db: AsyncSession, group: Group) -> Group:
    group.join_password = await _unique(db, Group.join_password, _new_password)
    group.invite_token = _new_invite_token()
    await _commit_unique(db, group, new_code=False)
    await db.refresh(group)
    return group


async def set_join_enabled(db: AsyncSession, group: Group, enabled: bool) -> Group:
    group.join_enabled = enabled
    await db.commit()
    await db.refresh(group)
    return group


async def member_counts(db: AsyncSession, group_ids: list[uuid.UUID]) -> dict[uuid.UUID, dict[str, int]]:
    if not group_ids:
        return {}
    rows = await db.execute(
        select(GroupMember.group_id, GroupMember.status, func.count())
        .where(GroupMember.group_id.in_(group_ids))
        .group_by(GroupMember.group_id, GroupMember.status)
    )
    out: dict[uuid.UUID, dict[str, int]] = {gid: {"active": 0, "pending": 0} for gid in group_ids}
    for gid, status, count in rows:
        if status in (MemberStatus.ACTIVE, MemberStatus.PENDING):
            out[gid][status] = count
    return out


async def find_joinable_group(db: AsyncSession, code: str) -> Group:
    group = await db.scalar(select(Group).where(Group.join_code == normalize_code(code)))
    if group is None or group.status != GroupStatus.ACTIVE:
        raise NotFound("GROUP_CODE_INVALID", "Bunday kodli guruh topilmadi. Kodni tekshiring")
    if not group.join_enabled:
        raise Forbidden(
            "JOIN_CLOSED",
            "Bu guruhga qo'shilish hozir yopiq. Ustozingizdan qo'shilishni ochib qo'yishini so'rang",
        )
    return group


async def _check_lock(db: AsyncSession, student_id: uuid.UUID, group_id: uuid.UUID) -> None:
    s = get_settings()
    since = utcnow() - timedelta(minutes=s.join_lock_minutes)
    failed = await db.scalar(
        select(func.count())
        .select_from(JoinAttempt)
        .where(
            JoinAttempt.student_id == student_id,
            JoinAttempt.group_id == group_id,
            JoinAttempt.success.is_(False),
            JoinAttempt.created_at >= since,
        )
    )
    if failed >= s.join_max_failed_attempts:
        raise TooManyRequests(
            "JOIN_LOCKED",
            f"Parol ko'p marta noto'g'ri kiritildi. {s.join_lock_minutes} daqiqadan keyin urinib ko'ring",
            details={"retry_after": s.join_lock_minutes * 60},
        )


async def _is_counted(db: AsyncSession, teacher_id: uuid.UUID, student_id: uuid.UUID) -> bool:
    """O'quvchi shu ustozning boshqa faol guruhida allaqachon hisoblanganmi (limitga ikki marta kirmasin)."""
    return bool(
        await db.scalar(
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
    )


async def join_group(
    db: AsyncSession, student: User, code: str, password: str | None, invite_token: str | None
) -> GroupMember:
    """So'rov yuboradi: natija doim PENDING, ustoz tasdiqlagach ACTIVE bo'ladi."""
    group = await find_joinable_group(db, code)
    await _check_lock(db, student.id, group.id)

    clean_password = normalize_password(password or "")
    via_token = bool(invite_token) and secrets.compare_digest(invite_token, group.invite_token)
    via_password = bool(clean_password) and secrets.compare_digest(clean_password, group.join_password)
    if not (via_token or via_password):
        db.add(JoinAttempt(student_id=student.id, group_id=group.id, success=False, created_at=utcnow()))
        await db.commit()
        if invite_token and not password:
            raise AppError("INVITE_EXPIRED", "Taklif havolasi eskirgan. Ustozingizdan yangi kod va parolni so'rang")
        raise AppError("GROUP_PASSWORD_INVALID", "Parol noto'g'ri")

    member = await db.scalar(
        select(GroupMember).where(GroupMember.group_id == group.id, GroupMember.student_id == student.id)
    )
    if member is not None and member.status == MemberStatus.ACTIVE:
        raise Conflict("ALREADY_MEMBER", "Siz allaqachon shu guruhdasiz")
    if member is not None and member.status == MemberStatus.PENDING:
        raise Conflict("ALREADY_PENDING", "So'rovingiz yuborilgan. Ustoz tasdiqlashini kuting")

    # Joy qolmagan bo'lsa, so'rovni ham qabul qilmaymiz: o'quvchi behuda kutib qolmasin
    plan = await plans.effective_plan(db, group.teacher_id)
    if plan is None:
        raise Forbidden("TEACHER_PLAN_EXPIRED", "Ustozingizning tarifi hozir faol emas. Ustozingizga xabar bering")
    if not await _is_counted(db, group.teacher_id, student.id) and (
        await plans.active_student_count(db, group.teacher_id) >= plan.max_students
    ):
        raise Forbidden("GROUP_FULL", "Guruhda joy qolmagan. Ustozingizga xabar bering")

    now = utcnow()
    if member is None:
        member = GroupMember(group_id=group.id, student_id=student.id, status=MemberStatus.PENDING)
        db.add(member)
    else:
        # Avval chiqarilgan/rad etilgan o'quvchi qayta so'rov yuboradi
        member.status = MemberStatus.PENDING
    member.decided_at = None
    db.add(JoinAttempt(student_id=student.id, group_id=group.id, success=True, created_at=now))
    try:
        await db.commit()
    except IntegrityError as exc:  # bir vaqtda ikki marta bosilgan
        await db.rollback()
        raise Conflict("ALREADY_PENDING", "So'rovingiz yuborilgan. Ustoz tasdiqlashini kuting") from exc
    await db.refresh(member)
    return member


def _limit_error(plan) -> Forbidden:
    return Forbidden(
        "PLAN_STUDENT_LIMIT",
        f"{plan.name} tarifida {plan.max_students} ta o'quvchi. Joy bo'shatish yoki tarifni yangilash kerak",
        details={"limit": plan.max_students, "plan": plan.code},
    )


async def decide_member(db: AsyncSession, group: Group, student_id: uuid.UUID, action: str) -> GroupMember:
    member = await db.scalar(
        select(GroupMember).where(GroupMember.group_id == group.id, GroupMember.student_id == student_id)
    )
    if member is None or member.status in (MemberStatus.REJECTED, MemberStatus.REMOVED):
        raise NotFound("MEMBER_NOT_FOUND", "O'quvchi topilmadi")

    if action == "approve":
        if member.status != MemberStatus.PENDING:
            raise Conflict("MEMBER_NOT_PENDING", "O'quvchi allaqachon guruhda")
        plan = await plans.require_plan(db, group.teacher_id)
        if not await _is_counted(db, group.teacher_id, student_id) and (
            await plans.active_student_count(db, group.teacher_id) >= plan.max_students
        ):
            raise _limit_error(plan)
        member.status = MemberStatus.ACTIVE
    elif action == "reject":
        if member.status != MemberStatus.PENDING:
            raise Conflict("MEMBER_NOT_PENDING", "O'quvchi allaqachon guruhda")
        member.status = MemberStatus.REJECTED
    elif action == "remove":
        member.status = MemberStatus.REMOVED
    else:
        raise AppError("ACTION_INVALID", "Noma'lum amal")
    member.decided_at = utcnow()
    await db.commit()
    await db.refresh(member)
    return member


async def approve_all(db: AsyncSession, group: Group) -> dict[str, int]:
    """Kutayotganlarning hammasini (so'rov tartibida) tarif limiti yetguncha qabul qiladi."""
    pending = list(
        await db.scalars(
            select(GroupMember)
            .where(GroupMember.group_id == group.id, GroupMember.status == MemberStatus.PENDING)
            .order_by(GroupMember.created_at)
        )
    )
    plan = await plans.require_plan(db, group.teacher_id)
    used = await plans.active_student_count(db, group.teacher_id)
    approved = 0
    now = utcnow()
    for member in pending:
        counted = await _is_counted(db, group.teacher_id, member.student_id)
        if not counted and used >= plan.max_students:
            break
        member.status = MemberStatus.ACTIVE
        member.decided_at = now
        approved += 1
        if not counted:
            used += 1
    await db.commit()
    return {"approved": approved, "left_pending": len(pending) - approved, "limit": plan.max_students}


async def teacher_has_student(db: AsyncSession, teacher_id: uuid.UUID, student_id: uuid.UUID) -> bool:
    return bool(
        await db.scalar(
            select(GroupMember.id)
            .join(Group, Group.id == GroupMember.group_id)
            .where(
                Group.teacher_id == teacher_id,
                GroupMember.student_id == student_id,
                GroupMember.status == MemberStatus.ACTIVE,
            )
            .limit(1)
        )
    )
