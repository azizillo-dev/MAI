import asyncio
import logging
from typing import Protocol

import httpx

from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.core.phone import mask_phone

log = logging.getLogger("sms")


class SmsSender(Protocol):
    async def send(self, phone: str, text: str) -> None: ...


class ConsoleSms:
    """Development: SMS yuborilmaydi, konsolga chiqariladi."""

    async def send(self, phone: str, text: str) -> None:
        log.warning("[SMS -> %s] %s", phone, text)


class EskizSms:
    """Eskiz.uz provayderi. Token 30 kun amal qiladi; 401 kelsa qayta olinadi.

    Diqqat: Eskiz faqat oldindan tasdiqlangan shablon matnlarini yuboradi.
    `otp_message()` matnini Eskiz kabinetida shablon sifatida tasdiqlatish kerak.
    """

    def __init__(self, settings: Settings) -> None:
        self._s = settings
        self._token: str | None = None
        self._lock = asyncio.Lock()
        self._client = httpx.AsyncClient(base_url=settings.eskiz_base_url, timeout=10)

    async def _login(self) -> str:
        resp = await self._client.post(
            "/auth/login", data={"email": self._s.eskiz_email, "password": self._s.eskiz_password}
        )
        resp.raise_for_status()
        return resp.json()["data"]["token"]

    async def _get_token(self, force: bool = False) -> str:
        async with self._lock:
            if force or self._token is None:
                self._token = await self._login()
            return self._token

    async def send(self, phone: str, text: str) -> None:
        payload = {"mobile_phone": phone.lstrip("+"), "message": text, "from": self._s.eskiz_from}
        try:
            for attempt in range(2):
                token = await self._get_token(force=attempt > 0)
                resp = await self._client.post(
                    "/message/sms/send", data=payload, headers={"Authorization": f"Bearer {token}"}
                )
                if resp.status_code == 401 and attempt == 0:
                    continue
                resp.raise_for_status()
                return
        except httpx.HTTPError as exc:
            log.error("Eskiz SMS xatosi (%s): %s", mask_phone(phone), exc)
            raise AppError("SMS_FAILED", "SMS yuborib bo'lmadi. Birozdan keyin qayta urinib ko'ring", 503) from exc


def otp_message(code: str) -> str:
    return f"Mentor AI: tasdiqlash kodi {code}. Kodni hech kimga bermang."


_sender: SmsSender | None = None


def get_sms_sender() -> SmsSender:
    global _sender
    if _sender is None:
        s = get_settings()
        _sender = EskizSms(s) if s.sms_provider == "eskiz" else ConsoleSms()
    return _sender
