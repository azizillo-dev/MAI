import logging
from contextlib import asynccontextmanager

from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse

from app.api.routes import admin, assignments, auth, gamification, groups, me, teachers
from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.db.session import get_sessionmaker
from app.services.assignments import resume_pending
from app.services.plans import seed_plans

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(_: FastAPI):
    async with get_sessionmaker()() as db:
        await seed_plans(db)
    await resume_pending()
    yield


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Mentor AI API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
    )
    register_error_handlers(app)
    for module in (auth, me, teachers, groups, gamification, admin):
        app.include_router(module.router, prefix="/api/v1")
    # /api/v1/... va /media/... yo'llari routerning o'zida
    app.include_router(assignments.router)

    admin_html = (Path(__file__).parent / "admin_web" / "index.html").read_text(encoding="utf-8")

    @app.get("/admin", include_in_schema=False)
    async def admin_panel() -> HTMLResponse:
        return HTMLResponse(admin_html, headers={"Cache-Control": "no-store"})

    @app.get("/health", include_in_schema=False)
    async def health() -> dict:
        return {"ok": True}

    return app


app = create_app()
