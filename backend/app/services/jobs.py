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
# Navbatda (hali boshlanmagan) turgan vazifalar: davriy tekshiruv bir ishni qayta-qayta qo'shmasin
_queued: set[tuple] = set()


def spawn(fn: Callable[..., Awaitable[None]], *args) -> None:
    key = (fn.__name__, *args)
    if key in _queued:
        return
    _queued.add(key)

    async def runner() -> None:
        async with _semaphore:
            # Boshlandi — navbatdan chiqadi (ish ichidan o'zini qayta navbatga qo'yishi mumkin)
            _queued.discard(key)
            try:
                await fn(*args)
            except Exception:  # vazifa yiqilsa ham server ishlashda davom etadi
                log.exception("Fon vazifasi xatosi: %s%s", fn.__name__, args)

    task = asyncio.create_task(runner())
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


def spawn_later(delay: float, fn: Callable[..., Awaitable[None]], *args) -> None:
    """Kechiktirilgan vazifa (AI limiti tugaganda qayta urinish). Server qayta ishga tushsa,
    `resume_pending()` baribir topib oladi — holat bazada saqlanadi."""

    async def later() -> None:
        await asyncio.sleep(delay)
        spawn(fn, *args)

    task = asyncio.create_task(later())
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


def start_periodic(interval: float, fn: Callable[[], Awaitable[None]]) -> asyncio.Task:
    """Davriy vazifa (masalan, to'xtab qolgan AI ishlarini qayta navbatga qo'yish)."""

    async def loop() -> None:
        while True:
            await asyncio.sleep(interval)
            try:
                await fn()
            except Exception:
                log.exception("Davriy vazifa xatosi: %s", fn.__name__)

    return asyncio.create_task(loop())


async def drain() -> None:
    """Testlar uchun: barcha fon vazifalari tugashini kutadi."""
    while _tasks:
        await asyncio.gather(*list(_tasks), return_exceptions=True)
