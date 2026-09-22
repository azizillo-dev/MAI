import uuid
from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, File, Form, Query, UploadFile
from fastapi.responses import Response
from sqlalchemy import func, select

from app.api.deps import DB, CurrentStudent, CurrentTeacher
from app.core.errors import AppError
from app.models import (
    Assignment,
    AssignmentStatus,
    Book,
    Group,
    GroupMember,
    GroupStatus,
    MemberStatus,
    Submission,
    SubmissionStatus,
)
from app.schemas.assignments import (
    AssignmentOut,
    BookOut,
    BookUpdateIn,
    ContentUpdateIn,
    ReviewIn,
    StudentAssignmentOut,
    SubmissionOut,
    SubmissionStats,
)
from app.schemas.common import Message
from app.services import assignments as svc
from app.services import groups as group_svc
from app.services.storage import get_storage, signed_url, verify_signature

router = APIRouter(tags=["assignments"])

MEDIA_TYPES = {".jpg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".pdf": "application/pdf"}


# ---------------------------------------------------------------- presenterlar


def book_out(b: Book) -> BookOut:
    return BookOut(
        id=b.id,
        title=b.title,
        page_count=b.page_count,
        page_offset=b.page_offset,
        last_printed_page=b.page_count - b.page_offset + 1,
    )


def assignment_out(a: Assignment, stats: SubmissionStats | None = None) -> AssignmentOut:
    return AssignmentOut(
        id=a.id,
        group_id=a.group_id,
        group_name=a.group.name,
        title=a.title,
        instructions=a.instructions,
        source_type=a.source_type,
        book=book_out(a.book) if a.book else None,
        page_from=a.page_from,
        page_to=a.page_to,
        problems=a.problems,
        items=a.items or [],
        rubric=a.rubric or [],
        image_urls=[signed_url(i.file_key) for i in a.images],
        prepare_error=a.prepare_error,
        status=a.status,
        due_at=a.due_at,
        allow_late=a.allow_late,
        late_penalty_percent=a.late_penalty_percent,
        published_at=a.published_at,
        created_at=a.created_at,
        stats=stats,
    )


def submission_out(s: Submission, *, for_teacher: bool) -> SubmissionOut:
    visible = for_teacher or s.status == SubmissionStatus.GRADED
    return SubmissionOut(
        id=s.id,
        assignment_id=s.assignment_id,
        student_id=s.student_id,
        student_name=s.student.full_name,
        status=s.status,
        submitted_at=s.submitted_at,
        is_late=s.is_late,
        attempt=s.attempt,
        text_answer=s.text_answer,
        file_urls=[signed_url(f.file_key) for f in s.files],
        # Ustoz tekshirmaguncha (needs_review) AI xulosasi o'quvchiga ko'rsatilmaydi
        ai_items=s.ai_items if visible else [],
        ai_confidence=s.ai_confidence if for_teacher else None,
        ai_matches_assignment=s.ai_matches_assignment if for_teacher else None,
        feedback_student=s.feedback_student if visible else None,
        note_teacher=s.note_teacher if for_teacher else None,
        ai_score_percent=s.ai_score_percent if for_teacher else None,
        teacher_score=s.teacher_score,
        teacher_comment=s.teacher_comment if visible else None,
        final_score=s.final_score if visible else None,
        grading_scale=s.assignment.group.grading_scale,
    )


async def _stats(db: DB, a: Assignment) -> SubmissionStats:
    rows = dict(
        (await db.execute(
            select(Submission.status, func.count()).where(Submission.assignment_id == a.id).group_by(Submission.status)
        )).all()
    )
    members = await db.scalar(
        select(func.count()).select_from(GroupMember).where(
            GroupMember.group_id == a.group_id, GroupMember.status == MemberStatus.ACTIVE
        )
    )
    return SubmissionStats(
        submitted=sum(rows.values()),
        graded=rows.get(SubmissionStatus.GRADED, 0),
        needs_review=rows.get(SubmissionStatus.NEEDS_REVIEW, 0) + rows.get(SubmissionStatus.FAILED, 0),
        members=members,
    )


async def _read_uploads(files: list[UploadFile] | None) -> list[bytes]:
    return [await f.read() for f in (files or []) if f.filename or f.size]


# ---------------------------------------------------------------- Fayllar


@router.get("/media/{key:path}", include_in_schema=False)
async def media(key: str, exp: int, sig: str) -> Response:
    verify_signature(key, exp, sig)
    data = get_storage().read(key)
    ext = key[key.rfind("."):]
    return Response(
        data,
        media_type=MEDIA_TYPES.get(ext, "application/octet-stream"),
        headers={"Cache-Control": "private, max-age=3600"},
    )


# ---------------------------------------------------------------- Kitoblar (o'qituvchi)


@router.post("/api/v1/books", response_model=BookOut, status_code=201)
async def upload_book(
    teacher: CurrentTeacher,
    db: DB,
    file: Annotated[UploadFile, File()],
    title: Annotated[str, Form(min_length=2, max_length=120)],
    page_offset: Annotated[int, Form(ge=1)] = 1,
) -> BookOut:
    return book_out(await svc.create_book(db, teacher, title.strip(), page_offset, await file.read()))


@router.get("/api/v1/books", response_model=list[BookOut])
async def list_books(teacher: CurrentTeacher, db: DB) -> list[BookOut]:
    rows = await db.scalars(select(Book).where(Book.teacher_id == teacher.id).order_by(Book.created_at.desc()))
    return [book_out(b) for b in rows]


@router.patch("/api/v1/books/{book_id}", response_model=BookOut)
async def update_book(book_id: uuid.UUID, body: BookUpdateIn, teacher: CurrentTeacher, db: DB) -> BookOut:
    book = await svc.get_teacher_book(db, teacher, book_id)
    if body.title is not None:
        book.title = body.title.strip()
    if body.page_offset is not None:
        if body.page_offset > book.page_count:
            raise AppError("PAGE_OFFSET_INVALID", f"1 dan {book.page_count} gacha bo'lishi kerak", 422)
        book.page_offset = body.page_offset
    await db.commit()
    await db.refresh(book)
    return book_out(book)


# ---------------------------------------------------------------- Vazifalar (o'qituvchi)


@router.post("/api/v1/assignments", response_model=AssignmentOut, status_code=201)
async def create_assignment(
    teacher: CurrentTeacher,
    db: DB,
    group_id: Annotated[uuid.UUID, Form()],
    title: Annotated[str, Form(min_length=2, max_length=120)],
    source_type: Annotated[Literal["book", "images", "text"], Form()],
    due_at: Annotated[datetime, Form()],
    instructions: Annotated[str | None, Form(max_length=4000)] = None,
    allow_late: Annotated[bool, Form()] = True,
    late_penalty_percent: Annotated[int, Form(ge=0, le=100)] = 0,
    book_id: Annotated[uuid.UUID | None, Form()] = None,
    page_from: Annotated[int | None, Form(ge=1)] = None,
    page_to: Annotated[int | None, Form(ge=1)] = None,
    problems: Annotated[str | None, Form(max_length=120)] = None,
    images: Annotated[list[UploadFile] | None, File()] = None,
) -> AssignmentOut:
    a = await svc.create_assignment(
        db,
        teacher,
        group_id=group_id,
        title=title.strip(),
        instructions=(instructions or "").strip() or None,
        source_type=source_type,
        due_at=due_at,
        allow_late=allow_late,
        late_penalty_percent=late_penalty_percent,
        book_id=book_id,
        page_from=page_from,
        page_to=page_to,
        problems=(problems or "").strip() or None,
        images=await _read_uploads(images),
    )
    return assignment_out(a)


@router.get("/api/v1/groups/{group_id}/assignments", response_model=list[AssignmentOut])
async def group_assignments(group_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> list[AssignmentOut]:
    group = await group_svc.get_teacher_group(db, teacher, group_id)
    rows = await db.scalars(
        select(Assignment).where(Assignment.group_id == group.id).order_by(Assignment.created_at.desc())
    )
    return [assignment_out(a, await _stats(db, a)) for a in rows]


@router.get("/api/v1/assignments/{assignment_id}", response_model=AssignmentOut)
async def get_assignment(assignment_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> AssignmentOut:
    a = await svc.get_teacher_assignment(db, teacher, assignment_id)
    return assignment_out(a, await _stats(db, a))


@router.put("/api/v1/assignments/{assignment_id}/content", response_model=AssignmentOut)
async def update_content(assignment_id: uuid.UUID, body: ContentUpdateIn, teacher: CurrentTeacher, db: DB) -> AssignmentOut:
    a = await svc.get_teacher_assignment(db, teacher, assignment_id)
    a = await svc.update_content(
        db,
        a,
        [i.model_dump() for i in body.items] if body.items is not None else None,
        [c.model_dump() for c in body.rubric] if body.rubric is not None else None,
    )
    return assignment_out(a)


@router.post("/api/v1/assignments/{assignment_id}/retry", response_model=AssignmentOut)
async def retry(assignment_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> AssignmentOut:
    a = await svc.retry_prepare(db, await svc.get_teacher_assignment(db, teacher, assignment_id))
    return assignment_out(a)


@router.post("/api/v1/assignments/{assignment_id}/publish", response_model=AssignmentOut)
async def publish(assignment_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> AssignmentOut:
    a = await svc.publish(db, await svc.get_teacher_assignment(db, teacher, assignment_id))
    return assignment_out(a, await _stats(db, a))


@router.delete("/api/v1/assignments/{assignment_id}", response_model=Message)
async def delete_assignment(assignment_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> Message:
    a = await svc.get_teacher_assignment(db, teacher, assignment_id)
    if await db.scalar(select(func.count()).select_from(Submission).where(Submission.assignment_id == a.id)):
        raise AppError("HAS_SUBMISSIONS", "O'quvchilar ish topshirgan vazifani o'chirib bo'lmaydi", 409)
    for img in a.images:
        get_storage().delete(img.file_key)
    await db.delete(a)
    await db.commit()
    return Message()


@router.get("/api/v1/assignments/{assignment_id}/submissions", response_model=list[SubmissionOut])
async def assignment_submissions(assignment_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> list[SubmissionOut]:
    a = await svc.get_teacher_assignment(db, teacher, assignment_id)
    rows = list(await db.scalars(select(Submission).where(Submission.assignment_id == a.id)))
    order = {SubmissionStatus.NEEDS_REVIEW: 0, SubmissionStatus.FAILED: 0, SubmissionStatus.GRADING: 1}
    rows.sort(key=lambda s: (order.get(s.status, 2), s.student.last_name))
    return [submission_out(s, for_teacher=True) for s in rows]


@router.get("/api/v1/teachers/me/review-queue", response_model=list[SubmissionOut])
async def review_queue(teacher: CurrentTeacher, db: DB) -> list[SubmissionOut]:
    """"Tekshirish kerak": AI ishonchi past, vazifaga mos emas yoki AI xato bergan ishlar."""
    rows = await db.scalars(
        select(Submission)
        .join(Assignment, Assignment.id == Submission.assignment_id)
        .where(
            Assignment.teacher_id == teacher.id,
            Submission.status.in_([SubmissionStatus.NEEDS_REVIEW, SubmissionStatus.FAILED]),
        )
        .order_by(Submission.submitted_at)
        .limit(100)
    )
    return [submission_out(s, for_teacher=True) for s in rows]


@router.get("/api/v1/submissions/{submission_id}", response_model=SubmissionOut)
async def get_submission(submission_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> SubmissionOut:
    s = await db.get(Submission, submission_id)
    if s is None or s.assignment.teacher_id != teacher.id:
        raise AppError("SUBMISSION_NOT_FOUND", "Ish topilmadi", 404)
    return submission_out(s, for_teacher=True)


@router.post("/api/v1/submissions/{submission_id}/review", response_model=SubmissionOut)
async def review(submission_id: uuid.UUID, body: ReviewIn, teacher: CurrentTeacher, db: DB) -> SubmissionOut:
    s = await svc.teacher_review(db, teacher, submission_id, body.score, body.comment)
    return submission_out(s, for_teacher=True)


# ---------------------------------------------------------------- O'quvchi


async def _student_view(db: DB, student, a: Assignment) -> StudentAssignmentOut:
    sub = await db.scalar(
        select(Submission).where(Submission.assignment_id == a.id, Submission.student_id == student.id)
    )
    return StudentAssignmentOut(
        id=a.id,
        group_id=a.group_id,
        group_name=a.group.name,
        subject=a.group.subject,
        teacher_name=a.group.teacher.full_name,
        title=a.title,
        instructions=a.instructions,
        source_type=a.source_type,
        # Javoblar kaliti o'quvchiga berilmaydi
        items=[{"number": i.get("number"), "text": i.get("text")} for i in (a.items or [])],
        rubric=a.rubric or [],
        image_urls=[signed_url(i.file_key) for i in a.images],
        book_title=a.book.title if a.book else None,
        page_from=a.page_from,
        page_to=a.page_to,
        problems=a.problems,
        due_at=a.due_at,
        allow_late=a.allow_late,
        late_penalty_percent=a.late_penalty_percent,
        grading_scale=a.group.grading_scale,
        submission=submission_out(sub, for_teacher=False) if sub else None,
    )


@router.get("/api/v1/student/assignments", response_model=list[StudentAssignmentOut])
async def student_assignments(
    student: CurrentStudent, db: DB, group_id: uuid.UUID | None = Query(None)
) -> list[StudentAssignmentOut]:
    q = (
        select(Assignment)
        .join(Group, Group.id == Assignment.group_id)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(
            GroupMember.student_id == student.id,
            GroupMember.status == MemberStatus.ACTIVE,
            Group.status == GroupStatus.ACTIVE,
            Assignment.status == AssignmentStatus.PUBLISHED,
        )
        .order_by(Assignment.due_at)
    )
    if group_id:
        q = q.where(Assignment.group_id == group_id)
    return [await _student_view(db, student, a) for a in await db.scalars(q)]


@router.get("/api/v1/student/assignments/{assignment_id}", response_model=StudentAssignmentOut)
async def student_assignment(assignment_id: uuid.UUID, student: CurrentStudent, db: DB) -> StudentAssignmentOut:
    return await _student_view(db, student, await svc.get_student_assignment(db, student, assignment_id))


@router.post("/api/v1/student/assignments/{assignment_id}/submission", response_model=StudentAssignmentOut, status_code=201)
async def submit(
    assignment_id: uuid.UUID,
    student: CurrentStudent,
    db: DB,
    files: Annotated[list[UploadFile] | None, File()] = None,
    text_answer: Annotated[str | None, Form(max_length=8000)] = None,
) -> StudentAssignmentOut:
    a = await svc.get_student_assignment(db, student, assignment_id)
    await svc.submit(db, student, a, await _read_uploads(files), text_answer)
    return await _student_view(db, student, a)

