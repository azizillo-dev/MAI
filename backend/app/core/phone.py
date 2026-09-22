import re

from app.core.errors import AppError

_DIGITS = re.compile(r"\D+")


def normalize_uz_phone(raw: str) -> str:
    """Har qanday yozilishni `+998XXXXXXXXX` ko'rinishiga keltiradi.

    Qabul qilinadi: "+998 90 123-45-67", "998901234567", "901234567", "(90) 123 45 67".
    """
    digits = _DIGITS.sub("", raw or "")
    if len(digits) == 9:
        digits = "998" + digits
    if len(digits) != 12 or not digits.startswith("998"):
        raise AppError("PHONE_INVALID", "Telefon raqam noto'g'ri. Namuna: +998 90 123 45 67", 422)
    return "+" + digits


def mask_phone(phone: str) -> str:
    """+998901234567 -> +998 90 *** ** 67 (loglar va ekranlar uchun)."""
    return f"{phone[:4]} {phone[4:6]} *** ** {phone[-2:]}"


_EMAIL = re.compile(r"^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$")


def normalize_email(raw: str) -> str:
    email = (raw or "").strip().lower()
    if len(email) > 254 or not _EMAIL.match(email):
        raise AppError("EMAIL_INVALID", "Email manzil noto'g'ri. Namuna: ism@gmail.com", 422)
    return email


def mask_email(email: str) -> str:
    """ali.valiyev@gmail.com -> al*******@gmail.com"""
    name, _, domain = email.partition("@")
    return f"{name[:2]}{'*' * max(len(name) - 2, 3)}@{domain}"
