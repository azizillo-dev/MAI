import os
import tempfile

os.environ.update(
    MEDIA_ROOT=tempfile.mkdtemp(prefix="mentor_media_"),
    AI_PROVIDER="fake",
    ENVIRONMENT="test",
    DATABASE_URL="sqlite+aiosqlite:///:memory:",
    OTP_DEV_ECHO="true",
    SMS_PROVIDER="console",
    JWT_SECRET="test-jwt-secret-0123456789abcdef0123456789",
    OTP_SECRET="test-otp-secret-0123456789abcdef0123456789",
)

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine  # noqa: E402

from app.db import session as db_session  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import Base  # noqa: E402
from app.services.plans import seed_plans  # noqa: E402


@pytest.fixture
async def client(tmp_path):
    # Fayl bazasi va alohida ulanishlar: fon vazifasi (AI baholash) so'rov sessiyasi bilan bitta
    # ulanishni bo'lishmaydi — Postgres'dagi haqiqiy holatga mos, tranzaksiyalar aralashib ketmaydi
    engine = create_async_engine(f"sqlite+aiosqlite:///{(tmp_path / 'test.db').as_posix()}", connect_args={"timeout": 30})
    db_session._engine = engine
    db_session._sessionmaker = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with db_session._sessionmaker() as db:
        await seed_plans(db)

    app = create_app()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    await engine.dispose()
    db_session._engine = db_session._sessionmaker = None


_phone_counter = iter(range(100_000, 999_999))


def next_phone() -> str:
    return f"+99890{next(_phone_counter):07d}"


async def login(client: AsyncClient, phone: str) -> dict:
    r = await client.post("/api/v1/auth/otp/request", json={"phone": phone})
    assert r.status_code == 200, r.text
    r = await client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": r.json()["dev_code"]})
    assert r.status_code == 200, r.text
    return r.json()


def auth(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


ONBOARDING = {
    "subjects": ["math"],
    "student_levels": ["grade_5_9"],
    "teaching_place": "learning_center",
    "grading_scale": "10",
    "checking_style": "balanced",
    "feedback_language": "uz",
    "notes": "Yechim yo'li yozilmasa ball kamaytirilsin",
}


async def make_teacher(client: AsyncClient, onboard: bool = True) -> dict:
    v = await login(client, next_phone())
    r = await client.post(
        "/api/v1/auth/register/teacher",
        json={"registration_token": v["registration_token"], "first_name": "azizillo", "last_name": "Nabiyev"},
    )
    assert r.status_code == 201, r.text
    h = auth(r.json()["tokens"])
    if onboard:
        r2 = await client.put("/api/v1/teachers/me/onboarding", json={"answers": ONBOARDING}, headers=h)
        assert r2.status_code == 200, r2.text
    return h


async def make_student(client: AsyncClient, first: str = "Ali", last: str = "Valiyev") -> dict:
    v = await login(client, next_phone())
    r = await client.post(
        "/api/v1/auth/register/student",
        json={
            "registration_token": v["registration_token"],
            "first_name": first,
            "last_name": last,
            "birth_date": "2012-05-14",
        },
    )
    assert r.status_code == 201, r.text
    return auth(r.json()["tokens"])
