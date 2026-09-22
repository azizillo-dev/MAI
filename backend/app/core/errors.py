"""Yagona xato formati.

Har bir xato mashina o'qiy oladigan `code` va o'zbekcha `message` bilan qaytadi:
    {"error": {"code": "OTP_INVALID", "message": "...", "details": {...}}}
Ilova `code` bo'yicha o'z tilida xabar ko'rsatadi, `message` esa zaxira.
"""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class AppError(Exception):
    status_code = 400

    def __init__(
        self,
        code: str,
        message: str,
        status_code: int | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}
        if status_code is not None:
            self.status_code = status_code


class NotFound(AppError):
    status_code = 404


class Forbidden(AppError):
    status_code = 403


class Unauthorized(AppError):
    status_code = 401


class Conflict(AppError):
    status_code = 409


class TooManyRequests(AppError):
    status_code = 429


def _body(code: str, message: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        headers = None
        retry_after = exc.details.get("retry_after")
        if exc.status_code == 429 and retry_after is not None:
            headers = {"Retry-After": str(retry_after)}
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(exc.code, exc.message, exc.details),
            headers=headers,
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        fields: dict[str, str] = {}
        for err in exc.errors():
            loc = [str(p) for p in err.get("loc", ()) if p not in ("body", "query", "path")]
            fields[".".join(loc) or "_"] = err.get("msg", "invalid")
        return JSONResponse(
            status_code=422,
            content=_body("VALIDATION_ERROR", "Ma'lumotlar noto'g'ri kiritilgan", {"fields": fields}),
        )
