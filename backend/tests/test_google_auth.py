import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.services import google_auth

CLIENT = "test-client.apps.googleusercontent.com"


@pytest.fixture
def google(monkeypatch):
    """Google o'rniga o'zimizning kalit: tekshiruv yo'li haqiqiydagidek (imzo, aud, iss, muddat)."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    class FakeJwks:
        def get_signing_key_from_jwt(self, token):
            return type("K", (), {"key": key.public_key()})()

    monkeypatch.setattr(google_auth, "_jwks", FakeJwks())
    monkeypatch.setattr(google_auth, "client_ids", lambda: [CLIENT])

    def token(email="ali.valiyev@gmail.com", verified=True, aud=CLIENT, iss="https://accounts.google.com", **extra):
        now = int(time.time())
        claims = {"iss": iss, "aud": aud, "sub": "123", "email": email, "email_verified": verified,
                  "given_name": "Ali", "family_name": "Valiyev", "iat": now, "exp": now + 600, **extra}
        return jwt.encode(claims, key, algorithm="RS256")

    return token


async def test_new_google_user_registers_then_logs_in(client, google):
    r = await client.post("/api/v1/auth/google", json={"id_token": google()})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "needs_registration" and body["registration_token"]
    assert (body["first_name"], body["last_name"]) == ("Ali", "Valiyev")  # forma oldindan to'ladi

    r = await client.post("/api/v1/auth/register/teacher", json={
        "registration_token": body["registration_token"], "first_name": "Ali", "last_name": "Valiyev"})
    assert r.status_code == 201, r.text
    assert r.json()["me"]["email"] == "ali.valiyev@gmail.com"

    # Ikkinchi marta — darhol kiradi
    r = await client.post("/api/v1/auth/google", json={"id_token": google(email="Ali.Valiyev@gmail.com")})
    assert r.json()["status"] == "logged_in" and r.json()["tokens"]["access_token"]


async def test_bad_google_tokens_rejected(client, google):
    bad = [
        google(verified=False),
        google(aud="someone-else.apps.googleusercontent.com"),
        google(iss="https://evil.example.com"),
        google(exp=int(time.time()) - 3600),
    ]
    for t in bad:
        r = await client.post("/api/v1/auth/google", json={"id_token": t})
        assert r.status_code == 401, r.text


async def test_google_not_configured(client, monkeypatch):
    monkeypatch.setattr(google_auth, "client_ids", lambda: [])
    r = await client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert r.status_code == 503 and r.json()["error"]["code"] == "GOOGLE_NOT_CONFIGURED"
