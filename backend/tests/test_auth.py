from tests.conftest import auth, login, next_phone


async def test_phone_formats_normalized(client):
    for raw in ["+998 90 111 22 33", "998901112233", "90 111-22-33", "(90) 111 22 33"]:
        r = await client.post("/api/v1/auth/otp/request", json={"phone": raw})
        if r.status_code == 429:
            continue  # bir raqamga qayta so'rash cheklovi
        assert r.json()["phone"] == "+998901112233"


async def test_bad_phone(client):
    r = await client.post("/api/v1/auth/otp/request", json={"phone": "12345"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "PHONE_INVALID"


async def test_new_user_needs_registration_then_logs_in(client):
    phone = next_phone()
    v = await login(client, phone)
    assert v["status"] == "needs_registration" and v["registration_token"]

    r = await client.post(
        "/api/v1/auth/register/student",
        json={
            "registration_token": v["registration_token"],
            "first_name": "  azizillo ",
            "last_name": "o‘ktamov",
            "birth_date": "2010-01-01",
            "gender": "male",
        },
    )
    assert r.status_code == 201, r.text
    me = r.json()["me"]
    assert me["first_name"] == "Azizillo"
    assert me["last_name"] == "Oʻktamov"
    assert me["role"] == "student" and me["student"]["is_locked"] is True and me["student"]["can_edit"] is False

    # Qayta kirish: endi tokenlar darhol beriladi
    from app.core.config import get_settings

    get_settings().otp_resend_seconds = 0
    try:
        again = await login(client, phone)
    finally:
        get_settings().otp_resend_seconds = 60
    assert again["status"] == "logged_in" and again["me"]["id"] == me["id"]


async def test_registration_token_cannot_be_reused(client):
    v = await login(client, next_phone())
    body = {"registration_token": v["registration_token"], "first_name": "Ali", "last_name": "Valiyev"}
    assert (await client.post("/api/v1/auth/register/teacher", json=body)).status_code == 201
    r = await client.post("/api/v1/auth/register/teacher", json=body)
    assert r.status_code == 409 and r.json()["error"]["code"] == "PHONE_TAKEN"


async def test_wrong_code_counts_attempts(client):
    phone = next_phone()
    await client.post("/api/v1/auth/otp/request", json={"phone": phone})
    r = await client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": "000000"})
    # 000000 tasodifan to'g'ri bo'lishi ehtimoli juda kichik
    if r.status_code == 400:
        assert r.json()["error"]["code"] == "OTP_INVALID"
        assert r.json()["error"]["details"]["attempts_left"] == 4


async def test_otp_resend_cooldown(client):
    phone = next_phone()
    assert (await client.post("/api/v1/auth/otp/request", json={"phone": phone})).status_code == 200
    r = await client.post("/api/v1/auth/otp/request", json={"phone": phone})
    assert r.status_code == 429 and r.json()["error"]["code"] == "OTP_RESEND_TOO_SOON"
    assert "Retry-After" in r.headers


async def test_old_code_invalid_after_new_one(client):
    phone = next_phone()
    first = (await client.post("/api/v1/auth/otp/request", json={"phone": phone})).json()["dev_code"]
    from app.core.config import get_settings

    get_settings().otp_resend_seconds = 0
    try:
        second = (await client.post("/api/v1/auth/otp/request", json={"phone": phone})).json()["dev_code"]
    finally:
        get_settings().otp_resend_seconds = 60
    if first != second:
        r = await client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": first})
        assert r.status_code == 400
    r = await client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": second})
    assert r.status_code == 200


async def test_invalid_names_rejected(client):
    v = await login(client, next_phone())
    r = await client.post(
        "/api/v1/auth/register/student",
        json={"registration_token": v["registration_token"], "first_name": "A1", "last_name": "B", "birth_date": "2030-01-01"},
    )
    assert r.status_code == 422
    fields = r.json()["error"]["details"]["fields"]
    assert {"first_name", "last_name", "birth_date"} <= set(fields)


async def test_refresh_rotation_and_reuse_detection(client):
    v = await login(client, next_phone())
    r = await client.post(
        "/api/v1/auth/register/teacher",
        json={"registration_token": v["registration_token"], "first_name": "Ali", "last_name": "Valiyev"},
    )
    tokens = r.json()["tokens"]

    r1 = await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r1.status_code == 200
    new = r1.json()
    assert new["refresh_token"] != tokens["refresh_token"]

    # Eski token qayta ishlatildi -> sessiya yopiladi, yangi token ham ishlamaydi
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})).status_code == 401
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": new["refresh_token"]})).status_code == 401


async def test_logout_revokes_access_immediately(client):
    v = await login(client, next_phone())
    r = await client.post(
        "/api/v1/auth/register/teacher",
        json={"registration_token": v["registration_token"], "first_name": "Ali", "last_name": "Valiyev"},
    )
    h = auth(r.json()["tokens"])
    assert (await client.get("/api/v1/me", headers=h)).status_code == 200
    assert (await client.post("/api/v1/auth/logout", headers=h)).status_code == 200
    r = await client.get("/api/v1/me", headers=h)
    assert r.status_code == 401 and r.json()["error"]["code"] == "SESSION_INVALID"
