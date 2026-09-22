import io
from datetime import UTC, datetime, timedelta

import pytest
from PIL import Image as PILImage
from pypdf import PdfWriter

from app.ai import provider as ai
from app.ai.schemas import GradedItem, GradeResult
from app.services import jobs
from app.services.assignments import to_scale, week_start_utc
from tests.conftest import make_student, make_teacher


def pdf_bytes(pages: int) -> bytes:
    w = PdfWriter()
    for _ in range(pages):
        w.add_blank_page(width=595, height=842)
    out = io.BytesIO()
    w.write(out)
    return out.getvalue()


def png_bytes(color=(200, 30, 30)) -> bytes:
    out = io.BytesIO()
    PILImage.new("RGB", (40, 40), color).save(out, format="PNG")
    return out.getvalue()


def due(hours=24) -> str:
    return (datetime.now(UTC) + timedelta(hours=hours)).isoformat()


async def _setup(client, n_students=1):
    t = await make_teacher(client)
    g = (await client.post("/api/v1/groups", json={"name": "7-B", "subject": "math"}, headers=t)).json()
    students = []
    for _ in range(n_students):
        s = await make_student(client)
        await client.post("/api/v1/memberships", json={"code": g["join_code"], "password": g["join_password"]}, headers=s)
        students.append(s)
    await client.post(f"/api/v1/groups/{g['id']}/members/approve-all", headers=t)
    return t, g, students


async def _book(client, t, pages=40, offset=5):
    r = await client.post(
        "/api/v1/books",
        headers=t,
        data={"title": "Algebra 7", "page_offset": str(offset)},
        files={"file": ("algebra.pdf", pdf_bytes(pages), "application/pdf")},
    )
    assert r.status_code == 201, r.text
    return r.json()


async def _book_assignment(client, t, g, **extra):
    book = await _book(client, t)
    data = {
        "group_id": g["id"], "title": "34-37 betlar", "source_type": "book", "book_id": book["id"],
        "page_from": "34", "page_to": "35", "problems": "56-60", "due_at": due(), **extra,
    }
    r = await client.post("/api/v1/assignments", headers=t, data=data)
    assert r.status_code == 201, r.text
    await jobs.drain()
    return (await client.get(f"/api/v1/assignments/{r.json()['id']}", headers=t)).json()


# ---------------------------------------------------------------- Kitob va tayyorlash


async def test_book_upload_and_page_offset(client):
    t, _, _ = await _setup(client, 0)
    book = await _book(client, t, pages=40, offset=5)
    assert book["page_count"] == 40 and book["last_printed_page"] == 36

    r = await client.post("/api/v1/books", headers=t, data={"title": "Soxta"},
                          files={"file": ("x.pdf", b"not a pdf", "application/pdf")})
    assert r.status_code == 422 and r.json()["error"]["code"] == "FILE_TYPE_INVALID"


async def test_book_assignment_prepared_then_published(client):
    t, g, _ = await _setup(client, 0)
    a = await _book_assignment(client, t, g)
    assert a["status"] == "review"
    assert [i["number"] for i in a["items"]] == ["56", "57", "58", "59", "60"]

    # Ustoz bitta misolni tuzatadi va o'chiradi
    items = a["items"][:4]
    items[0]["text"] = "2x + 3 = 11"
    r = await client.put(f"/api/v1/assignments/{a['id']}/content", headers=t, json={"items": items})
    assert r.status_code == 200 and len(r.json()["items"]) == 4

    r = await client.post(f"/api/v1/assignments/{a['id']}/publish", headers=t)
    assert r.json()["status"] == "published" and r.json()["stats"]["members"] == 0


async def test_page_range_outside_book(client):
    t, g, _ = await _setup(client, 0)
    book = await _book(client, t, pages=40, offset=5)  # bosma betlar 1..36
    r = await client.post("/api/v1/assignments", headers=t, data={
        "group_id": g["id"], "title": "Sinov vazifa", "source_type": "book", "book_id": book["id"],
        "page_from": "35", "page_to": "37", "due_at": due()})
    assert r.status_code == 422 and r.json()["error"]["code"] == "PAGES_OUT_OF_RANGE", r.text


async def test_images_and_text_sources(client):
    t, g, _ = await _setup(client, 0)
    r = await client.post("/api/v1/assignments", headers=t,
                          data={"group_id": g["id"], "title": "Rasmdagi misollar", "source_type": "images", "due_at": due()},
                          files=[("images", ("a.png", png_bytes(), "image/png"))])
    assert r.status_code == 201, r.text
    assert len(r.json()["image_urls"]) == 1

    r = await client.post("/api/v1/assignments", headers=t, data={
        "group_id": g["id"], "title": "Krossvord", "source_type": "text", "due_at": due(),
        "instructions": "Hayvonlar mavzusida 15 so'zli krossvord tuzib keling"})
    assert r.status_code == 201
    await jobs.drain()
    a = (await client.get(f"/api/v1/assignments/{r.json()['id']}", headers=t)).json()
    assert a["status"] == "review" and sum(c["weight"] for c in a["rubric"]) == 100


async def test_fake_jpg_rejected(client):
    t, g, _ = await _setup(client, 0)
    r = await client.post("/api/v1/assignments", headers=t,
                          data={"group_id": g["id"], "title": "Sinov vazifa", "source_type": "images", "due_at": due()},
                          files=[("images", ("virus.jpg", b"MZ\x90\x00 not an image", "image/jpeg"))])
    assert r.status_code == 422 and r.json()["error"]["code"] == "FILE_TYPE_INVALID"


async def test_weekly_limit_when_plan_has_one(client):
    from sqlalchemy import update

    from app.db import session as db_session
    from app.models import Plan

    # Hozirgi tariflarda haftalik limit yo'q; admin yoqsa ishlashini tekshiramiz
    async with db_session.get_sessionmaker()() as db:
        await db.execute(update(Plan).where(Plan.code == "trial").values(max_assignments_per_week=4))
        await db.commit()
    t, g, _ = await _setup(client, 0)
    body = {"group_id": g["id"], "source_type": "text", "due_at": due(), "instructions": "Insho yozing: Mening oilam"}
    for i in range(4):
        assert (await client.post("/api/v1/assignments", headers=t, data={**body, "title": f"V{i}"})).status_code == 201
    r = await client.post("/api/v1/assignments", headers=t, data={**body, "title": "V5"})
    assert r.status_code == 403 and r.json()["error"]["code"] == "PLAN_ASSIGNMENT_LIMIT"
    await jobs.drain()


async def test_ai_failure_marks_failed_and_teacher_can_fill_manually(client, monkeypatch):
    t, g, _ = await _setup(client, 0)

    async def boom(*a, **k):
        raise ai.AiError("AI xizmatiga ulanib bo'lmadi")

    monkeypatch.setattr(ai.get_provider(), "extract_from_pdf", boom)
    a = await _book_assignment(client, t, g)
    assert a["status"] == "failed" and "ulanib" in a["prepare_error"]

    r = await client.put(f"/api/v1/assignments/{a['id']}/content", headers=t,
                         json={"items": [{"number": "1", "text": "2+2", "answer": "4"}]})
    assert r.json()["status"] == "review"
    assert (await client.post(f"/api/v1/assignments/{a['id']}/publish", headers=t)).status_code == 200


# ---------------------------------------------------------------- Topshirish va baholash


async def _published(client, t, g, **extra):
    a = await _book_assignment(client, t, g, **extra)
    await client.post(f"/api/v1/assignments/{a['id']}/publish", headers=t)
    return a


async def _submit(client, s, a, color=(10, 120, 200)):
    return await client.post(f"/api/v1/student/assignments/{a['id']}/submission", headers=s,
                             files=[("files", ("work.png", png_bytes(color), "image/png"))])


async def test_student_submits_and_gets_grade(client):
    t, g, (s,) = await _setup(client, 1)
    a = await _published(client, t, g)

    lst = (await client.get("/api/v1/student/assignments", headers=s)).json()
    assert len(lst) == 1 and lst[0]["submission"] is None
    assert all("answer" not in i for i in lst[0]["items"])  # javoblar kaliti o'quvchiga berilmaydi

    r = await _submit(client, s, a)
    assert r.status_code == 201 and r.json()["submission"]["status"] == "grading"
    await jobs.drain()

    sub = (await client.get(f"/api/v1/student/assignments/{a['id']}", headers=s)).json()["submission"]
    assert sub["status"] == "graded"
    assert sub["final_score"] == 8.0  # fake: 85% -> guruh 10 ballik (ustoz onboardingda tanlagan) -> 8
    assert sub["feedback_student"] and sub["note_teacher"] is None  # ustoz izohi o'quvchiga ko'rinmaydi
    assert len(sub["ai_items"]) == 5

    teacher_view = (await client.get(f"/api/v1/assignments/{a['id']}/submissions", headers=t)).json()
    assert teacher_view[0]["note_teacher"] and teacher_view[0]["ai_confidence"] == 0.9


async def test_low_confidence_goes_to_teacher_first(client, monkeypatch):
    t, g, (s,) = await _setup(client, 1)
    a = await _published(client, t, g)

    async def unsure(ctx, work, text):
        return GradeResult(matches_assignment=True, items=[GradedItem(number="56", verdict="partial", comment="")],
                           score_percent=60, feedback_student="...", note_teacher="Rasm xira", confidence=0.4), ai.Usage("fake", "fake")

    monkeypatch.setattr(ai.get_provider(), "grade", unsure)
    await _submit(client, s, a)
    await jobs.drain()

    sub = (await client.get(f"/api/v1/student/assignments/{a['id']}", headers=s)).json()["submission"]
    assert sub["status"] == "needs_review" and sub["final_score"] is None and sub["feedback_student"] is None

    queue = (await client.get("/api/v1/teachers/me/review-queue", headers=t)).json()
    assert len(queue) == 1
    r = await client.post(f"/api/v1/submissions/{queue[0]['id']}/review", headers=t, json={"score": 3, "comment": "Toza yozing"})
    assert r.status_code == 200 and r.json()["final_score"] == 3

    sub = (await client.get(f"/api/v1/student/assignments/{a['id']}", headers=s)).json()["submission"]
    assert sub["status"] == "graded" and sub["final_score"] == 3 and sub["teacher_comment"] == "Toza yozing"
    assert (await client.get("/api/v1/teachers/me/review-queue", headers=t)).json() == []


async def test_same_photo_from_two_students_flagged(client):
    t, g, (s1, s2) = await _setup(client, 2)
    a = await _published(client, t, g)
    await _submit(client, s1, a, color=(1, 2, 3))
    await jobs.drain()
    await _submit(client, s2, a, color=(1, 2, 3))
    await jobs.drain()
    sub2 = (await client.get(f"/api/v1/student/assignments/{a['id']}", headers=s2)).json()["submission"]
    assert sub2["status"] == "needs_review"
    queue = (await client.get("/api/v1/teachers/me/review-queue", headers=t)).json()
    assert "aynan shu rasmni" in queue[0]["note_teacher"]


async def test_non_member_cannot_see_or_submit(client):
    t, g, _ = await _setup(client, 0)
    a = await _published(client, t, g)
    outsider = await make_student(client)
    assert (await client.get(f"/api/v1/student/assignments/{a['id']}", headers=outsider)).status_code == 404
    assert (await _submit(client, outsider, a)).status_code == 404


async def test_unpublished_hidden_from_students(client):
    t, g, (s,) = await _setup(client, 1)
    await _book_assignment(client, t, g)  # review holatida
    assert (await client.get("/api/v1/student/assignments", headers=s)).json() == []


async def test_resubmit_and_limits(client):
    t, g, (s,) = await _setup(client, 1)
    a = await _published(client, t, g)
    for attempt in range(1, 4):
        r = await _submit(client, s, a, color=(attempt, 0, 0))
        assert r.status_code == 201, r.text
        assert r.json()["submission"]["attempt"] == attempt
        await jobs.drain()
    r = await _submit(client, s, a)
    assert r.status_code == 409 and r.json()["error"]["code"] == "RESUBMIT_LIMIT"


async def test_media_links_are_signed(client):
    t, g, (s,) = await _setup(client, 1)
    a = await _published(client, t, g)
    await _submit(client, s, a)
    await jobs.drain()
    url = (await client.get(f"/api/v1/student/assignments/{a['id']}", headers=s)).json()["submission"]["file_urls"][0]
    path = url.split("://", 1)[1].split("/", 1)[1]
    assert (await client.get("/" + path)).status_code == 200
    assert (await client.get("/" + path.replace("sig=", "sig=0"))).status_code == 404
    assert (await client.get("/" + path.split("?")[0] + "?exp=1&sig=x")).status_code == 404


# ---------------------------------------------------------------- Yordamchilar


@pytest.mark.parametrize(
    ("percent", "scale", "expected"),
    [(100, "5", 5), (86, "5", 5), (85, "5", 4), (71, "5", 4), (51, "5", 3), (50, "5", 2),
     (85, "10", 8), (3, "10", 1), (84.6, "100", 85)],
)
def test_to_scale(percent, scale, expected):
    assert to_scale(percent, scale) == expected


def test_week_starts_monday_tashkent():
    # Yakshanba 20:00 UTC = dushanba 01:00 Toshkent -> hafta shu dushanbadan boshlanadi
    sunday_evening = datetime(2026, 9, 20, 20, 0, tzinfo=UTC)
    assert week_start_utc(sunday_evening) == datetime(2026, 9, 20, 19, 0, tzinfo=UTC)


async def test_teacher_dashboard(client):
    t, g, (s1, s2) = await _setup(client, 2)
    empty = (await client.get("/api/v1/teachers/me/dashboard", headers=t)).json()
    assert empty["stats"]["students"] == 2 and empty["stats"]["open_assignments"] == 0
    assert len(empty["activity"]) == 7 and empty["stats"]["avg_percent_week"] is None

    a = await _published(client, t, g)
    await _submit(client, s1, a)
    await jobs.drain()

    d = (await client.get("/api/v1/teachers/me/dashboard", headers=t)).json()
    assert d["stats"]["open_assignments"] == 1 and d["stats"]["graded_this_week"] == 1
    assert d["stats"]["avg_percent_week"] == 80.0  # 10 ballik: 85% -> 8 -> 80%
    assert d["upcoming"][0]["submitted"] == 1 and d["upcoming"][0]["members"] == 2
    assert d["recent"][0]["final_score"] == 8.0
    assert sum(x["count"] for x in d["activity"]) == 1

    # Boshqa o'qituvchi bu ma'lumotlarni ko'rmaydi
    other = await make_teacher(client)
    assert (await client.get("/api/v1/teachers/me/dashboard", headers=other)).json()["stats"]["students"] == 0
