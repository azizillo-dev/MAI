"""Vazifalar: yaratish -> AI tayyorlaydi -> ustoz tasdiqlaydi -> nashr -> o'quvchi topshiradi -> AI baholaydi.

Holatlar:
  Assignment: preparing -> review -> published   (xato bo'lsa failed; ustoz qayta urinadi)
  Submission: grading -> graded | needs_review | failed; ustoz istalgan vaqtda bahoni o'zgartiradi
"""

import hashlib
import io
import logging
import uuid
from datetime import UTC, datetime, timedelta, timezone

from pypdf import PdfReader, PdfWriter
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.provider import AiError, GradingContext, Image, Usage, get_provider
from app.core.config import get_settings
from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.core.security import as_utc, utcnow
from app.db.session import get_sessionmaker
from app.models import (
    AiRun,
    Assignment,
    AssignmentImage,
    AssignmentStatus,
    Book,
    Group,
    GroupMember,
    GroupStatus,
    MemberStatus,
    SourceType,
    Submission,
    SubmissionFile,
    SubmissionStatus,
    User,
)
from app.services import jobs, plans
from app.services.storage import check_pdf, check_size, get_storage, sniff_image

log = logging.getLogger("assignments")

# O'zbekistonda yozgi vaqt yo'q: doim UTC+5
TASHKENT = timezone(timedelta(hours=5))
MAX_RESUBMITS = 3


# ---------------------------------------------------------------- Kitoblar


async def create_book(db: AsyncSession, teacher: User, title: str, page_offset: int, data: bytes) -> Book:
    s = get_settings()
    check_size(data, s.max_pdf_mb, "PDF")
    check_pdf(data)
    try:
        page_count = len(PdfReader(io.BytesIO(data)).pages)
    except Exception as exc:
        raise AppError("PDF_BROKEN", "PDF faylni o'qib bo'lmadi. Boshqa faylni yuklang", 422) from exc
    if page_offset < 1 or page_offset > page_count:
        raise AppError("PAGE_OFFSET_INVALID", f"1 dan {page_count} gacha bo'lishi kerak", 422)
    key = get_storage().save(f"books/{teacher.id}", data, ".pdf")
    book = Book(teacher_id=teacher.id, title=title, file_key=key, page_count=page_count, page_offset=page_offset)
    db.add(book)
    await db.commit()
    await db.refresh(book)
    return book


async def get_teacher_book(db: AsyncSession, teacher: User, book_id: uuid.UUID) -> Book:
    book = await db.get(Book, book_id)
    if book is None or book.teacher_id != teacher.id:
        raise NotFound("BOOK_NOT_FOUND", "Kitob topilmadi")
    return book


def slice_pdf(data: bytes, first_pdf_page: int, last_pdf_page: int) -> bytes:
    """Faqat kerakli sahifalar AI ga yuboriladi: tezroq, arzonroq va aniqroq."""
    reader = PdfReader(io.BytesIO(data))
    writer = PdfWriter()
    for i in range(first_pdf_page - 1, last_pdf_page):
        writer.add_page(reader.pages[i])
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


# ---------------------------------------------------------------- Vazifa yaratish


def week_start_utc(now: datetime | None = None) -> datetime:
    """Joriy haftaning dushanba 00:00 (Toshkent vaqti), UTC da."""
    local = (now or utcnow()).astimezone(TASHKENT)
    monday = (local - timedelta(days=local.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    return monday.astimezone(UTC)


async def assignments_this_week(db: AsyncSession, teacher_id: uuid.UUID) -> int:
    return await db.scalar(
        select(func.count())
        .select_from(Assignment)
        .where(Assignment.teacher_id == teacher_id, Assignment.created_at >= week_start_utc())
    )


async def _check_week_limit(db: AsyncSession, teacher_id: uuid.UUID) -> None:
    plan = await plans.require_plan(db, teacher_id)
    limit = plan.max_assignments_per_week
    if limit is not None and await assignments_this_week(db, teacher_id) >= limit:
        raise Forbidden(
            "PLAN_ASSIGNMENT_LIMIT",
            f"{plan.name} tarifida haftasiga {limit} ta vazifa berish mumkin. Keyingi dushanbadan yana ochiladi",
            details={"limit": limit, "plan": plan.code},
        )


async def create_assignment(
    db: AsyncSession,
    teacher: User,
    *,
    group_id: uuid.UUID,
    title: str,
    instructions: str | None,
    source_type: str,
    due_at: datetime,
    allow_late: bool,
    late_penalty_percent: int,
    book_id: uuid.UUID | None = None,
    page_from: int | None = None,
    page_to: int | None = None,
    problems: str | None = None,
    images: list[bytes] | None = None,
) -> Assignment:
    s = get_settings()
    group = await db.get(Group, group_id)
    if group is None or group.teacher_id != teacher.id or group.status != GroupStatus.ACTIVE:
        raise NotFound("GROUP_NOT_FOUND", "Guruh topilmadi")
    if as_utc(due_at) < utcnow() + timedelta(minutes=10):
        raise AppError("DUE_INVALID", "Topshirish muddati kamida 10 daqiqa keyin bo'lishi kerak", 422)
    await _check_week_limit(db, teacher.id)

    assignment = Assignment(
        group_id=group.id,
        teacher_id=teacher.id,
        title=title,
        instructions=instructions,
        source_type=source_type,
        due_at=due_at,
        allow_late=allow_late,
        late_penalty_percent=late_penalty_percent,
        status=AssignmentStatus.PREPARING,
        items=[],
        rubric=[],
    )

    if source_type == SourceType.BOOK:
        if book_id is None or page_from is None or page_to is None:
            raise AppError("BOOK_REQUIRED", "Kitob va sahifalar oralig'ini tanlang", 422)
        book = await get_teacher_book(db, teacher, book_id)
        if page_to < page_from:
            raise AppError("PAGES_INVALID", "Oxirgi sahifa birinchisidan kichik bo'lmasin", 422)
        if page_to - page_from + 1 > s.max_book_pages_per_assignment:
            raise AppError(
                "PAGES_TOO_MANY", f"Bir vazifaga ko'pi bilan {s.max_book_pages_per_assignment} sahifa", 422
            )
        last_pdf_page = page_to + book.page_offset - 1
        if page_from < 1 or last_pdf_page > book.page_count:
            max_printed = book.page_count - book.page_offset + 1
            raise AppError("PAGES_OUT_OF_RANGE", f"Kitobda {max_printed}-betdan keyingi sahifa yo'q", 422)
        assignment.book_id = book.id
        assignment.page_from, assignment.page_to, assignment.problems = page_from, page_to, problems
    elif source_type == SourceType.IMAGES:
        if not images:
            raise AppError("IMAGES_REQUIRED", "Kamida bitta rasm yuklang", 422)
        if len(images) > 10:
            raise AppError("IMAGES_TOO_MANY", "Ko'pi bilan 10 ta rasm", 422)
        for pos, data in enumerate(images):
            check_size(data, s.max_image_mb, "Rasm")
            mime, ext = sniff_image(data)
            key = get_storage().save(f"assignments/{group.id}", data, ext)
            assignment.images.append(AssignmentImage(file_key=key, mime=mime, position=pos))
    elif source_type == SourceType.TEXT:
        if not instructions or len(instructions.strip()) < 10:
            raise AppError("INSTRUCTIONS_REQUIRED", "Topshiriqni batafsilroq yozing (kamida 10 belgi)", 422)
    else:
        raise AppError("SOURCE_INVALID", "Noma'lum vazifa turi", 422)

    db.add(assignment)
    await db.commit()
    await db.refresh(assignment)
    jobs.spawn(prepare_assignment, assignment.id)
    return assignment


# ---------------------------------------------------------------- AI tayyorlash


async def _log_run(db: AsyncSession, kind: str, usage: Usage | None, *, teacher_id, assignment_id=None,
                   submission_id=None, error: str | None = None) -> None:
    s = get_settings()
    u = usage or Usage(provider=s.ai_provider, model=s.ai_model)
    db.add(
        AiRun(
            kind=kind,
            teacher_id=teacher_id,
            assignment_id=assignment_id,
            submission_id=submission_id,
            provider=u.provider,
            model=u.model,
            input_tokens=u.input_tokens,
            output_tokens=u.output_tokens,
            cache_read_tokens=u.cache_read_tokens,
            cache_write_tokens=u.cache_write_tokens,
            duration_ms=u.duration_ms,
            success=error is None,
            error=error,
            created_at=utcnow(),
        )
    )


async def prepare_assignment(assignment_id: uuid.UUID) -> None:
    """Fon vazifasi: misollarni ajratadi yoki rubrika tuzadi, so'ng ustoz tasdiqlashiga qo'yadi."""
    provider = get_provider()
    async with get_sessionmaker()() as db:
        a = await db.get(Assignment, assignment_id)
        if a is None or a.status != AssignmentStatus.PREPARING:
            return
        storage = get_storage()
        subject = a.group.subject
        try:
            if a.source_type == SourceType.BOOK:
                book = a.book
                if book is None:
                    raise AiError("Kitob o'chirilgan")
                pdf = slice_pdf(
                    storage.read(book.file_key),
                    a.page_from + book.page_offset - 1,
                    a.page_to + book.page_offset - 1,
                )
                result, usage = await provider.extract_from_pdf(pdf, subject, a.problems)
                a.items = [i.model_dump() for i in result.items]
                a.prepare_error = result.notes
            elif a.source_type == SourceType.IMAGES:
                images = [Image(storage.read(img.file_key), img.mime) for img in a.images]
                result, usage = await provider.extract_from_images(images, subject)
                a.items = [i.model_dump() for i in result.items]
                a.prepare_error = result.notes
            else:
                rubric, usage = await provider.build_rubric(a.title, a.instructions or "", subject)
                a.rubric = [c.model_dump() for c in rubric.criteria]
                a.prepare_error = None
            if a.source_type != SourceType.TEXT and not a.items:
                raise AiError("Sahifalarda misol topilmadi. Sahifa oralig'ini tekshiring yoki misollarni qo'lda kiriting")
            a.status = AssignmentStatus.REVIEW
            await _log_run(db, "prepare", usage, teacher_id=a.teacher_id, assignment_id=a.id)
        except AiError as exc:
            a.status = AssignmentStatus.FAILED
            a.prepare_error = str(exc)
            await _log_run(db, "prepare", None, teacher_id=a.teacher_id, assignment_id=a.id, error=str(exc))
        except Exception as exc:
            log.exception("Vazifani tayyorlashda kutilmagan xato")
            a.status = AssignmentStatus.FAILED
            a.prepare_error = "Kutilmagan xato. Qayta urinib ko'ring yoki misollarni qo'lda kiriting"
            await _log_run(db, "prepare", None, teacher_id=a.teacher_id, assignment_id=a.id, error=repr(exc))
        await db.commit()


async def get_teacher_assignment(db: AsyncSession, teacher: User, assignment_id: uuid.UUID) -> Assignment:
    a = await db.get(Assignment, assignment_id)
    if a is None or a.teacher_id != teacher.id:
        raise NotFound("ASSIGNMENT_NOT_FOUND", "Vazifa topilmadi")
    return a


async def retry_prepare(db: AsyncSession, a: Assignment) -> Assignment:
    if a.status not in (AssignmentStatus.FAILED, AssignmentStatus.REVIEW):
        raise Conflict("ASSIGNMENT_STATE", "Vazifa hozir qayta tayyorlanmaydi")
    a.status = AssignmentStatus.PREPARING
    a.prepare_error = None
    await db.commit()
    jobs.spawn(prepare_assignment, a.id)
    return a


async def update_content(db: AsyncSession, a: Assignment, items: list[dict] | None, rubric: list[dict] | None) -> Assignment:
    """Ustoz AI ajratgan misollarni tuzatadi. Nashrdan keyin ham mumkin (keyingi tekshiruvlarga ta'sir qiladi)."""
    if a.status == AssignmentStatus.PREPARING:
        raise Conflict("ASSIGNMENT_STATE", "AI hali tayyorlamoqda, biroz kuting")
    if items is not None:
        a.items = items
    if rubric is not None:
        a.rubric = rubric
    if a.status == AssignmentStatus.FAILED and (a.items or a.rubric):
        a.status = AssignmentStatus.REVIEW  # qo'lda to'ldirildi
        a.prepare_error = None
    await db.commit()
    await db.refresh(a)
    return a


async def publish(db: AsyncSession, a: Assignment) -> Assignment:
    if a.status == AssignmentStatus.PUBLISHED:
        return a
    if a.status != AssignmentStatus.REVIEW:
        raise Conflict("ASSIGNMENT_STATE", "Avval AI tayyorlashi tugashini kuting")
    if a.source_type == SourceType.TEXT and not a.rubric:
        raise AppError("RUBRIC_REQUIRED", "Kamida bitta baholash mezoni bo'lishi kerak", 422)
    if a.source_type != SourceType.TEXT and not a.items:
        raise AppError("ITEMS_REQUIRED", "Kamida bitta misol bo'lishi kerak", 422)
    a.status = AssignmentStatus.PUBLISHED
    a.published_at = utcnow()
    await db.commit()
    await db.refresh(a)
    return a


# ---------------------------------------------------------------- O'quvchi: topshirish


async def _active_membership(db: AsyncSession, student_id: uuid.UUID, group_id: uuid.UUID) -> bool:
    return bool(
        await db.scalar(
            select(GroupMember.id).where(
                GroupMember.group_id == group_id,
                GroupMember.student_id == student_id,
                GroupMember.status == MemberStatus.ACTIVE,
            )
        )
    )


async def get_student_assignment(db: AsyncSession, student: User, assignment_id: uuid.UUID) -> Assignment:
    a = await db.get(Assignment, assignment_id)
    if (
        a is None
        or a.status != AssignmentStatus.PUBLISHED
        or not await _active_membership(db, student.id, a.group_id)
    ):
        raise NotFound("ASSIGNMENT_NOT_FOUND", "Vazifa topilmadi")
    return a


async def submit(
    db: AsyncSession, student: User, a: Assignment, files: list[bytes], text_answer: str | None
) -> Submission:
    s = get_settings()
    now = utcnow()
    late = now > as_utc(a.due_at)
    if late and not a.allow_late:
        raise Forbidden("DEADLINE_PASSED", "Topshirish muddati tugagan")
    if not files and not (text_answer and text_answer.strip()):
        raise AppError("WORK_REQUIRED", "Ishingizni rasmga olib yuklang", 422)
    if len(files) > s.max_images_per_submission:
        raise AppError("IMAGES_TOO_MANY", f"Ko'pi bilan {s.max_images_per_submission} ta rasm", 422)

    checked: list[tuple[bytes, str, str]] = []
    for data in files:
        check_size(data, s.max_image_mb, "Rasm")
        mime, ext = sniff_image(data)
        checked.append((data, mime, ext))

    sub = await db.scalar(
        select(Submission).where(Submission.assignment_id == a.id, Submission.student_id == student.id)
    )
    if sub is not None:
        # Qayta topshirish: faqat muddat ichida, ustoz baholamagan bo'lsa va urinishlar tugamagan bo'lsa
        if sub.reviewed_at is not None:
            raise Conflict("ALREADY_REVIEWED", "Ustoz ishingizni baholab bo'lgan")
        if late:
            raise Conflict("RESUBMIT_LATE", "Muddat tugagach qayta topshirib bo'lmaydi")
        if sub.status == SubmissionStatus.GRADING:
            raise Conflict("STILL_GRADING", "Oldingi ishingiz hali tekshirilmoqda")
        if sub.attempt >= MAX_RESUBMITS:
            raise Conflict("RESUBMIT_LIMIT", f"Ko'pi bilan {MAX_RESUBMITS} marta topshirish mumkin")
        for f in list(sub.files):
            get_storage().delete(f.file_key)
        sub.files.clear()
        sub.attempt += 1
    else:
        sub = Submission(assignment_id=a.id, student_id=student.id, attempt=1)
        db.add(sub)

    sub.text_answer = (text_answer or "").strip() or None
    sub.submitted_at = now
    sub.is_late = late
    sub.status = SubmissionStatus.GRADING
    sub.ai_items, sub.ai_score_percent, sub.ai_confidence = [], None, None
    sub.feedback_student = sub.note_teacher = None
    sub.final_score = None
    sub.graded_at = None
    if sub.attempt > 1:
        await _gamify(db, sub)  # qayta topshirildi: eski XP bekor, yangi baho kutiladi
    for pos, (data, mime, ext) in enumerate(checked):
        key = get_storage().save(f"submissions/{a.id}", data, ext)
        sub.files.append(
            SubmissionFile(file_key=key, mime=mime, position=pos, sha256=hashlib.sha256(data).hexdigest())
        )
    await db.commit()
    await db.refresh(sub)
    jobs.spawn(grade_submission, sub.id)
    return sub


# ---------------------------------------------------------------- AI baholash


async def _gamify(db: AsyncSession, sub: Submission) -> None:
    # gamification assignments'dan TASHKENT'ni oladi: aylanma importni oldini olish uchun shu yerda
    from app.services.gamification import on_submission_final

    await on_submission_final(db, sub)


def to_scale(percent: float, scale: str) -> float:
    """Foizni guruh shkalasiga o'tkazadi. 5 ballik: maktabdagi odatiy chegaralar."""
    p = max(0.0, min(100.0, percent))
    if scale == "5":
        return 5.0 if p >= 86 else 4.0 if p >= 71 else 3.0 if p >= 51 else 2.0
    if scale == "10":
        return float(max(1, round(p / 10)))
    return float(round(p))


def _with_penalty(percent: float, sub: Submission) -> float:
    if sub.is_late and sub.assignment.late_penalty_percent:
        return percent * (100 - sub.assignment.late_penalty_percent) / 100
    return percent


async def _duplicate_signal(db: AsyncSession, sub: Submission) -> str | None:
    """Boshqa o'quvchi aynan shu rasmni yuborganmi (ko'chirish belgisi)."""
    hashes = [f.sha256 for f in sub.files]
    if not hashes:
        return None
    other = await db.scalar(
        select(User)
        .join(Submission, Submission.student_id == User.id)
        .join(SubmissionFile, SubmissionFile.submission_id == Submission.id)
        .where(
            Submission.assignment_id == sub.assignment_id,
            Submission.id != sub.id,
            SubmissionFile.sha256.in_(hashes),
        )
        .limit(1)
    )
    return f"Diqqat: {other.full_name} aynan shu rasmni yuborgan." if other else None


async def grade_submission(submission_id: uuid.UUID) -> None:
    s = get_settings()
    provider = get_provider()
    async with get_sessionmaker()() as db:
        sub = await db.get(Submission, submission_id)
        if sub is None or sub.status != SubmissionStatus.GRADING:
            return
        a = sub.assignment
        teacher = await db.get(User, a.teacher_id)
        answers = (teacher.teacher.onboarding_answers if teacher and teacher.teacher else {}) or {}
        ctx = GradingContext(
            teacher_context=(teacher.teacher.ai_context if teacher and teacher.teacher else "") or "",
            subject=a.group.subject,
            grading_scale=a.group.grading_scale,
            title=a.title,
            instructions=a.instructions,
            items=a.items or [],
            rubric=a.rubric or [],
            feedback_language=answers.get("feedback_language", "uz"),
        )
        storage = get_storage()
        work = [Image(storage.read(f.file_key), f.mime) for f in sub.files]
        try:
            result, usage = await provider.grade(ctx, work, sub.text_answer)
        except AiError as exc:
            sub.status = SubmissionStatus.FAILED
            sub.note_teacher = f"AI tekshira olmadi: {exc}. Iltimos, qo'lda baholang."
            await _log_run(db, "grade", None, teacher_id=a.teacher_id, submission_id=sub.id, error=str(exc))
            await db.commit()
            return

        percent = float(max(0, min(100, result.score_percent)))
        confidence = max(0.0, min(1.0, result.confidence))
        sub.ai_items = [i.model_dump() for i in result.items]
        sub.ai_score_percent = percent
        sub.ai_confidence = confidence
        sub.ai_matches_assignment = result.matches_assignment
        sub.feedback_student = result.feedback_student
        sub.note_teacher = result.note_teacher
        sub.graded_at = utcnow()

        duplicate = await _duplicate_signal(db, sub)
        if duplicate:
            sub.note_teacher = f"{duplicate} {sub.note_teacher}"

        needs_teacher = confidence < s.ai_min_confidence or not result.matches_assignment or duplicate
        if needs_teacher:
            sub.status = SubmissionStatus.NEEDS_REVIEW
            sub.final_score = None  # ustoz ko'rmaguncha o'quvchiga baho chiqmaydi
        else:
            sub.status = SubmissionStatus.GRADED
            sub.final_score = to_scale(_with_penalty(percent, sub), a.group.grading_scale)
        await _log_run(db, "grade", usage, teacher_id=a.teacher_id, submission_id=sub.id)
        await _gamify(db, sub)
        await db.commit()


async def teacher_review(db: AsyncSession, teacher: User, submission_id: uuid.UUID, score: float,
                         comment: str | None) -> Submission:
    sub = await db.get(Submission, submission_id)
    if sub is None or sub.assignment.teacher_id != teacher.id:
        raise NotFound("SUBMISSION_NOT_FOUND", "Ish topilmadi")
    if sub.status == SubmissionStatus.GRADING:
        raise Conflict("STILL_GRADING", "AI hali tekshirmoqda, biroz kuting")
    scale = float(sub.assignment.group.grading_scale)
    if not 0 <= score <= scale:
        raise AppError("SCORE_INVALID", f"Baho 0 dan {int(scale)} gacha bo'lishi kerak", 422)
    sub.teacher_score = score
    sub.teacher_comment = (comment or "").strip() or None
    sub.final_score = score
    sub.reviewed_at = utcnow()
    sub.status = SubmissionStatus.GRADED
    await _gamify(db, sub)
    await db.commit()
    await db.refresh(sub)
    return sub


async def resume_pending() -> None:
    """Server qayta ishga tushganda chala qolgan AI ishlarini qayta navbatga qo'yadi."""
    async with get_sessionmaker()() as db:
        for aid in await db.scalars(select(Assignment.id).where(Assignment.status == AssignmentStatus.PREPARING)):
            jobs.spawn(prepare_assignment, aid)
        for sid in await db.scalars(select(Submission.id).where(Submission.status == SubmissionStatus.GRADING)):
            jobs.spawn(grade_submission, sid)
