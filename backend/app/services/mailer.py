"""Email yuborish. Development'da konsolga, production'da SMTP (Gmail app password) orqali."""

import asyncio
import logging
import smtplib
import ssl
from email.message import EmailMessage
from typing import Protocol

from app.core.config import get_settings
from app.core.errors import AppError

log = logging.getLogger("mailer")


class Mailer(Protocol):
    async def send(self, to: str, subject: str, text: str, html: str | None = None) -> None: ...


class ConsoleMailer:
    async def send(self, to: str, subject: str, text: str, html: str | None = None) -> None:
        log.warning("[EMAIL -> %s] %s | %s", to, subject, text)


class SmtpMailer:
    def _send_sync(self, msg: EmailMessage) -> None:
        s = get_settings()
        with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=20) as smtp:
            smtp.starttls(context=ssl.create_default_context())
            smtp.login(s.smtp_user, s.smtp_password)
            smtp.send_message(msg)

    async def send(self, to: str, subject: str, text: str, html: str | None = None) -> None:
        s = get_settings()
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = f"{s.email_from_name} <{s.smtp_user}>"
        msg["To"] = to
        msg.set_content(text)
        if html:
            msg.add_alternative(html, subtype="html")
        try:
            # smtplib bloklovchi: server qotib qolmasligi uchun alohida oqimda
            await asyncio.to_thread(self._send_sync, msg)
        except (smtplib.SMTPException, OSError) as exc:
            log.error("SMTP xatosi: %s", exc)
            raise AppError("EMAIL_FAILED", "Xat yuborib bo'lmadi. Email manzilini tekshirib, qayta urinib ko'ring", 503) from exc


def otp_email(code: str) -> tuple[str, str, str]:
    subject = f"Mentor AI: tasdiqlash kodi {code}"
    text = f"Tasdiqlash kodingiz: {code}\n\nKod 3 daqiqa amal qiladi. Uni hech kimga bermang."
    html = f"""<!doctype html><html><body style="margin:0;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif">
<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 12px">
<table width="100%" style="max-width:440px;background:#ffffff;border-radius:20px;overflow:hidden" cellpadding="0" cellspacing="0">
<tr><td style="background:linear-gradient(135deg,#4f46e5,#0ea5e9);background-color:#4f46e5;padding:28px;text-align:center">
<div style="color:#ffffff;font-size:22px;font-weight:bold">Mentor AI</div>
<div style="color:#e0e7ff;font-size:14px;margin-top:4px">Uy vazifalarini AI tekshiradi</div></td></tr>
<tr><td style="padding:28px;text-align:center">
<div style="color:#334155;font-size:15px">Tasdiqlash kodingiz:</div>
<div style="font-size:38px;letter-spacing:10px;font-weight:bold;color:#0f172a;margin:14px 0">{code}</div>
<div style="color:#64748b;font-size:13px">Kod 3 daqiqa amal qiladi. Uni hech kimga bermang —<br>Mentor AI xodimlari hech qachon kod so'ramaydi.</div>
</td></tr></table></td></tr></table></body></html>"""
    return subject, text, html


_mailer: Mailer | None = None


def get_mailer() -> Mailer:
    global _mailer
    if _mailer is None:
        _mailer = SmtpMailer() if get_settings().email_provider == "smtp" else ConsoleMailer()
    return _mailer
