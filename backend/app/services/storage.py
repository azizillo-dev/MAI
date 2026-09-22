"""Fayl saqlash. Hozir lokal disk; production'da shu interfeys bilan S3/R2 ga almashtiriladi.

Fayllar ochiq berilmaydi: telefon imzolangan, muddatli havola orqali oladi
(`/media/<key>?exp=...&sig=...`). Havolani bilgan boshqa odam muddat tugagach ocholmaydi.
"""

import hashlib
import hmac
import secrets
import time
from pathlib import Path

from app.core.config import get_settings
from app.core.errors import AppError, NotFound

IMAGE_TYPES = {
    b"\xff\xd8\xff": ("image/jpeg", ".jpg"),
    b"\x89PNG\r\n\x1a\n": ("image/png", ".png"),
    b"RIFF": ("image/webp", ".webp"),  # + "WEBP" 8-baytda tekshiriladi
}


def sniff_image(data: bytes) -> tuple[str, str]:
    """Kengaytmaga emas, fayl ichiga qarab turini aniqlaydi (soxta .jpg dan himoya)."""
    for magic, (mime, ext) in IMAGE_TYPES.items():
        if data.startswith(magic):
            if mime == "image/webp" and data[8:12] != b"WEBP":
                continue
            return mime, ext
    raise AppError("FILE_TYPE_INVALID", "Faqat JPG, PNG yoki WEBP rasm yuklash mumkin", 422)


def check_pdf(data: bytes) -> None:
    if not data.startswith(b"%PDF"):
        raise AppError("FILE_TYPE_INVALID", "Fayl PDF emas", 422)


def check_size(data: bytes, max_mb: int, what: str) -> None:
    if len(data) > max_mb * 1024 * 1024:
        raise AppError("FILE_TOO_LARGE", f"{what} hajmi {max_mb} MB dan oshmasin", 413)
    if not data:
        raise AppError("FILE_EMPTY", "Fayl bo'sh", 422)


class LocalStorage:
    def __init__(self, root: str) -> None:
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        path = (self.root / key).resolve()
        if self.root not in path.parents:  # "../" orqali boshqa papkaga chiqishdan himoya
            raise NotFound("FILE_NOT_FOUND", "Fayl topilmadi")
        return path

    def save(self, folder: str, data: bytes, ext: str) -> str:
        key = f"{folder}/{secrets.token_hex(16)}{ext}"
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return key

    def read(self, key: str) -> bytes:
        path = self._path(key)
        if not path.is_file():
            raise NotFound("FILE_NOT_FOUND", "Fayl topilmadi")
        return path.read_bytes()

    def delete(self, key: str) -> None:
        path = self._path(key)
        if path.is_file():
            path.unlink()


def _sign(key: str, exp: int) -> str:
    secret = get_settings().jwt_secret.encode()
    return hmac.new(secret, f"{key}:{exp}".encode(), hashlib.sha256).hexdigest()[:32]


def signed_url(key: str) -> str:
    s = get_settings()
    exp = int(time.time()) + s.media_url_ttl_seconds
    return f"{s.public_api_url}/media/{key}?exp={exp}&sig={_sign(key, exp)}"


def verify_signature(key: str, exp: int, sig: str) -> None:
    if exp < time.time() or not hmac.compare_digest(_sign(key, exp), sig):
        raise NotFound("FILE_NOT_FOUND", "Havola muddati tugagan")


_storage: LocalStorage | None = None


def get_storage() -> LocalStorage:
    global _storage
    if _storage is None:
        _storage = LocalStorage(get_settings().media_root)
    return _storage
