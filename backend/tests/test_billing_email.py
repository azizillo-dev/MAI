from datetime import UTC, datetime, timedelta

from sqlalchemy import update

from app.cli import create_admin
from app.db import session as db_session
from app.models import Subscription
from tests.conftest import auth, make_student, make_teacher


async def _email_login(client, email):
    r = await client.post("/api/v1/auth/email/request", json={"email": email})
    assert r.status_code == 200, r.text
    assert r.json()["channel"] == "email" and r.json()["target"] == email.strip().lower()
    r = await client.post("/api/v1/auth/email/verify", json={"email": email, "code": r.json()["dev_code"]})
    assert r.status_code == 200, r.text
    return r.json()


async def test_email_signup_and_login(client):
    v = await _email_login(client, "  Ustoz.Aziz@Gmail.com ")
    assert v["status"] == "needs_registration"
    r = await client.post("/api/v1/auth/register/teacher", json={
        "registration_token": v["registration_token"], "first_name": "Aziz", "last_name": "Karimov"})
    assert r.status_code == 201, r.text
    me = r.json()["me"]
    assert me["email"] == "ustoz.aziz@gmail.com" and me["phone"] is None

    from app.core.config import get_settings
    get_settings().otp_resend_seconds = 0
    try:
        again = await _email_login(client, "ustoz.aziz@gmail.com")
    finally:
        get_settings().otp_resend_seconds = 60
    assert again["status"] == "logged_in" and again["me"]["id"] == me["id"]


async def test_bad_email_rejected(client):
    r = await client.post("/api/v1/auth/email/request", json={"email": "not-an-email"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "EMAIL_INVALID"


async def test_trial_then_expired_blocks_creation(client):
    t = await make_teacher(client)
    plan = (await client.get("/api/v1/teachers/me/plan", headers=t)).json()
    assert plan["status"] == "trial" and plan["plan"]["max_students"] == 30

    async with db_session.get_sessionmaker()() as db:
        await db.execute(update(Subscription).values(current_period_end=datetime.now(UTC) - timedelta(days=1)))
        await db.commit()
    plan = (await client.get("/api/v1/teachers/me/plan", headers=t)).json()
    assert plan["status"] == "expired" and plan["days_left"] == 0
    r = await client.post("/api/v1/groups", json={"name": "7-A", "subject": "math"}, headers=t)
    assert r.status_code == 403 and r.json()["error"]["code"] == "PLAN_EXPIRED"


async def _admin(client) -> dict:
    await create_admin("admin@mentorai.uz", "Sirli-parol-123", "Bosh Admin")
    r = await client.post("/api/v1/admin/login", json={"email": "admin@mentorai.uz", "password": "Sirli-parol-123"})
    assert r.status_code == 200, r.text
    return auth(r.json()["tokens"])


async def test_plan_request_approved_by_admin(client):
    t = await make_teacher(client)
    plans = (await client.get("/api/v1/teachers/plans", headers=t)).json()["plans"]
    assert [(p["code"], p["price_uzs"], p["max_groups"], p["max_students"]) for p in plans] == [
        ("standard", 20000, 1, 30), ("pro", 70000, 3, 90)]

    r = await client.post("/api/v1/teachers/me/plan-requests", headers=t, json={"plan_code": "pro", "months": 2})
    assert r.status_code == 201 and r.json()["amount_uzs"] == 140000
    dup = await client.post("/api/v1/teachers/me/plan-requests", headers=t, json={"plan_code": "standard", "months": 1})
    assert dup.status_code == 409

    a = await _admin(client)
    pending = (await client.get("/api/v1/admin/requests", headers=a)).json()
    assert len(pending) == 1
    r = await client.post(f"/api/v1/admin/requests/{pending[0]['id']}/approve", headers=a, json={"note": "Click orqali"})
    assert r.json()["status"] == "approved"

    plan = (await client.get("/api/v1/teachers/me/plan", headers=t)).json()
    assert plan["plan"]["code"] == "pro" and plan["status"] == "active" and plan["days_left"] >= 59
    stats = (await client.get("/api/v1/admin/stats", headers=a)).json()
    assert stats["revenue_month"] == 140000 and stats["subscriptions"]["active"] == 1
    # Pro'da 3 guruh ochiladi
    for i in range(3):
        assert (await client.post("/api/v1/groups", json={"name": f"G{i}", "subject": "math"}, headers=t)).status_code == 201


async def test_admin_edit_plan_grant_and_permissions(client):
    a = await _admin(client)
    t = await make_teacher(client)
    s = await make_student(client)
    assert (await client.get("/api/v1/admin/stats", headers=t)).status_code == 403
    assert (await client.get("/api/v1/admin/stats", headers=s)).status_code == 403
    bad = await client.post("/api/v1/admin/login", json={"email": "admin@mentorai.uz", "password": "noto'g'ri-parol"})
    assert bad.status_code == 401

    plans = (await client.get("/api/v1/admin/plans", headers=a)).json()
    std = next(p for p in plans if p["code"] == "standard")
    r = await client.patch(f"/api/v1/admin/plans/{std['id']}", headers=a, json={"price_uzs": 25000})
    assert r.json()["price_uzs"] == 25000

    teachers = (await client.get("/api/v1/admin/teachers", headers=a)).json()
    tid = teachers[0]["id"]
    r = await client.post(f"/api/v1/admin/teachers/{tid}/grant", headers=a, json={"plan_code": "standard", "months": 1})
    assert r.json()["plan"]["code"] == "standard" and r.json()["status"] == "active"

    r = await client.post(f"/api/v1/admin/teachers/{tid}/block", headers=a)
    assert r.json()["is_active"] is False
    assert (await client.get("/api/v1/me", headers=t)).status_code == 401


async def test_admin_page_served(client):
    r = await client.get("/admin")
    assert r.status_code == 200 and "Mentor AI Admin" in r.text


async def test_sms_disabled_mode(client):
    from app.core.config import get_settings
    get_settings().sms_provider = "disabled"
    try:
        r = await client.post("/api/v1/auth/otp/request", json={"phone": "+998901234567"})
    finally:
        get_settings().sms_provider = "console"
    assert r.status_code == 503 and r.json()["error"]["code"] == "SMS_DISABLED"
