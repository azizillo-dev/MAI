from collections.abc import AsyncIterator

from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine:
    global _engine, _sessionmaker
    if _engine is None:
        s = get_settings()
        url = s.database_url
        kwargs: dict = {}
        if not url.startswith("sqlite"):
            kwargs = {
                # Har bir jarayon uchun: workers * (pool_size + max_overflow) Postgres limitidan oshmasin
                "pool_size": s.db_pool_size,
                "max_overflow": s.db_max_overflow,
                "pool_pre_ping": True,
                "pool_recycle": 1800,
            }
            parsed = make_url(url)
            # Shu kompyuterdagi bazaga shifrlash (SSL) shart emas va u CPU'ni behuda sarflaydi
            if parsed.host in ("localhost", "127.0.0.1", "::1") and "ssl" not in parsed.query:
                kwargs["connect_args"] = {"ssl": False}
        _engine = create_async_engine(url, **kwargs)
        _sessionmaker = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine


def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    get_engine()
    assert _sessionmaker is not None
    return _sessionmaker


async def get_db() -> AsyncIterator[AsyncSession]:
    async with get_sessionmaker()() as session:
        yield session
