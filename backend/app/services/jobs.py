"""Fon vazifalari (AI tayyorlash va baholash).

MVP uchun jarayon ichidagi asyncio vazifalari: so'rov darhol javob qaytaradi, AI fonda ishlaydi.
Server qayta ishga tushsa, chala qolganlar `resume_pending()` orqali qayta navbatga qo'yiladi.
Yuklama oshganda shu interfeys saqlangan holda Redis + worker (arq/Celery) ga ko'chiriladi.
"""

import asyncio
import logging
from collections.abc import Awaitable, Callable

log = logging.getLogger("jobs")

_tasks: set[asyncio.Task] = set()
# Bir vaqtda nechta AI so'rovi: API limitlari va xotirani himoya qiladi
_semaphore = asyncio.Semaphore(4)


def spawn(fn: Callable[..., Awaitable[None]], *args) -> None:
    async def runner() -> None:
        async with _semaphore:
            try:
                await fn(*args)
            except Exception:  # vazifa yiqilsa ham server ishlashda davom etadi
                log.exception("Fon vazifasi xatosi: %s%s", fn.__name__, args)

    task = asyncio.create_task(runner())
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def drain() -> None:
    """Testlar uchun: barcha fon vazifalari tugashini kutadi."""
    while _tasks:
        await asyncio.gather(*list(_tasks), return_exceptions=True)
