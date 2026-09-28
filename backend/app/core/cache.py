"""Jarayon ichidagi qisqa muddatli kesh (reyting, progress kabi og'ir hisob-kitoblar uchun).

Har bir jarayonning (worker) o'z keshi bor. Ma'lumot o'zgarganda shu jarayonda darhol tozalanadi,
boshqa jarayonlarda esa muddat (TTL) tugagach yangilanadi — bir necha soniyalik kechikish reyting
uchun sezilmaydi, server yuklamasi esa keskin kamayadi.
"""

import time
from collections import OrderedDict
from collections.abc import Hashable
from typing import Any


class TTLCache:
    def __init__(self, ttl: float, max_items: int = 5000) -> None:
        self.ttl = ttl
        self.max_items = max_items
        self._data: OrderedDict[Hashable, tuple[float, Any]] = OrderedDict()

    def get(self, key: Hashable) -> Any | None:
        item = self._data.get(key)
        if item is None:
            return None
        expires, value = item
        if expires < time.monotonic():
            self._data.pop(key, None)
            return None
        return value

    def set(self, key: Hashable, value: Any) -> None:
        if self.ttl <= 0:
            return
        self._data[key] = (time.monotonic() + self.ttl, value)
        self._data.move_to_end(key)
        while len(self._data) > self.max_items:
            self._data.popitem(last=False)

    def invalidate(self, predicate) -> None:
        """Shartga mos kalitlarni o'chiradi (masalan, bitta guruhga tegishli hamma yozuvlar)."""
        for key in [k for k in self._data if predicate(k)]:
            self._data.pop(key, None)

    def clear(self) -> None:
        self._data.clear()
