import re
from datetime import date
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict

# Lotin, kirill, o'zbekcha apostroflar (' ʻ ʼ ‘ ’ `) va chiziqcha
_NAME_RE = re.compile(r"^[A-Za-zА-Яа-яЁёЎўҚқҒғҲҳ'ʻʼ‘’`\- ]+$")
_APOSTROPHES = str.maketrans({"`": "ʻ", "‘": "ʻ", "’": "ʼ"})


def _clean_name(value: str) -> str:
    value = " ".join(value.split()).translate(_APOSTROPHES)
    if not 2 <= len(value) <= 40:
        raise ValueError("2 dan 40 gacha harf bo'lishi kerak")
    if not _NAME_RE.match(value):
        raise ValueError("Faqat harflardan iborat bo'lishi kerak")
    # "aZIZILLO" -> "Azizillo", "abdul-aziz" -> "Abdul-Aziz"
    return "-".join(p[:1].upper() + p[1:].lower() for p in value.split("-"))


PersonName = Annotated[str, AfterValidator(_clean_name)]


def _check_birth_date(value: date) -> date:
    today = date.today()
    age = today.year - value.year - ((today.month, today.day) < (value.month, value.day))
    if age < 4 or age > 90:
        raise ValueError("Tug'ilgan sana noto'g'ri")
    return value


BirthDate = Annotated[date, AfterValidator(_check_birth_date)]


class Schema(BaseModel):
    model_config = ConfigDict(from_attributes=True, str_strip_whitespace=True)


class Message(Schema):
    ok: bool = True
    message: str | None = None
