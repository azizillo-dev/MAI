"""Yuklama testi: ilovaning odatiy so'rovlarini parallel yuboradi va tezlikni o'lchaydi.

Server bilan bir xil JWT_SECRET va test bazasi kerak (tokenlar shu yerda yaratiladi):
    DATABASE_URL=... JWT_SECRET=... python -m tools.loadtest.run --base http://127.0.0.1:8200 \
        --concurrency 100 --duration 30

90% so'rov o'quvchilardan, 10% o'qituvchilardan (real nisbatga yaqin). Kutish vaqti yo'q —
bu serverning maksimal o'tkazuvchanligini ko'rsatadi.
"""

import argparse
import asyncio
import json
import pathlib
import random
import statistics
import time
import uuid
from collections import defaultdict
from datetime import timedelta

import httpx


async def prepare(sample: int) -> tuple[list[dict], list[dict]]:
    from sqlalchemy import insert, select

    from app.core.security import create_access_token, hash_token, new_refresh_token, utcnow
    from app.db.session import get_sessionmaker
    from app.models import Assignment, AuthSession, Group, GroupMember, User

    now = utcnow()
    async with get_sessionmaker()() as db:
        # Faqat guruhga a'zo o'quvchilar (guruhsizlar vazifa va reyting sahifalarini ochmaydi)
        students = list(await db.scalars(
            select(User).where(User.role == "student", User.id.in_(select(GroupMember.student_id))).limit(sample)
        ))
        teachers = list(await db.scalars(select(User).where(User.role == "teacher").limit(max(10, sample // 9))))
        s_group = dict((await db.execute(
            select(GroupMember.student_id, GroupMember.group_id).where(GroupMember.student_id.in_([u.id for u in students]))
        )).all())
        t_groups: dict = defaultdict(list)
        for gid, tid in (await db.execute(select(Group.id, Group.teacher_id).where(Group.teacher_id.in_([u.id for u in teachers])))).all():
            t_groups[tid].append(gid)
        g_assign: dict = defaultdict(list)
        for aid, gid in (await db.execute(select(Assignment.id, Assignment.group_id))).all():
            g_assign[gid].append(aid)
        g_members: dict = defaultdict(list)
        for sid, gid in (await db.execute(select(GroupMember.student_id, GroupMember.group_id))).all():
            g_members[gid].append(sid)

        sessions, out_s, out_t = [], [], []
        for u in students + teachers:
            sid = uuid.uuid4()
            sessions.append({"id": sid, "user_id": u.id, "refresh_token_hash": hash_token(new_refresh_token()),
                             "created_at": now, "last_used_at": now, "expires_at": now + timedelta(days=1)})
            token = {"Authorization": f"Bearer {create_access_token(u.id, u.role, sid)}"}
            if u.role == "student":
                gid = s_group[u.id]
                out_s.append({"h": token, "group": gid, "assignments": g_assign[gid]})
            else:
                gids = t_groups[u.id]
                out_t.append({"h": token, "groups": gids, "assignments": [a for g in gids for a in g_assign[g]],
                              "students": [s for g in gids for s in g_members[g]]})
        await db.execute(insert(AuthSession), sessions)
        await db.commit()
    return out_s, out_t


def student_request(u: dict) -> tuple[str, str]:
    a = random.choice(u["assignments"])
    return random.choices(
        [("me", "/api/v1/me"), ("memberships", "/api/v1/memberships"),
         ("student tasks", "/api/v1/student/assignments"), ("student task", f"/api/v1/student/assignments/{a}"),
         ("progress", "/api/v1/students/me/progress"), ("leaderboard", f"/api/v1/leaderboard?group_id={u['group']}")],
        weights=[15, 10, 25, 15, 20, 15],
    )[0]


def teacher_request(u: dict) -> tuple[str, str]:
    g, a, s = random.choice(u["groups"]), random.choice(u["assignments"]), random.choice(u["students"])
    return random.choices(
        [("me", "/api/v1/me"), ("dashboard", "/api/v1/teachers/me/dashboard"), ("groups", "/api/v1/groups"),
         ("members", f"/api/v1/groups/{g}/members"), ("submissions", f"/api/v1/assignments/{a}/submissions"),
         ("student profile", f"/api/v1/students/{s}/profile")],
        weights=[10, 30, 15, 15, 20, 10],
    )[0]


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8200")
    ap.add_argument("--concurrency", type=int, default=100)
    ap.add_argument("--duration", type=int, default=30)
    ap.add_argument("--sample", type=int, default=900)
    # Server tashqarisidan sinash uchun: tokenlarni serverda tayyorlab faylga yozish / fayldan o'qish
    ap.add_argument("--dump", help="tayyorlangan foydalanuvchilarni JSON faylga yozib chiqish")
    ap.add_argument("--load", help="bazaga ulanmasdan, JSON fayldan o'qish")
    args = ap.parse_args()

    if args.load:
        data = json.loads(pathlib.Path(args.load).read_text())
        students, teachers = data["students"], data["teachers"]
    else:
        students, teachers = await prepare(args.sample)
    if args.dump:
        pathlib.Path(args.dump).write_text(json.dumps({"students": students, "teachers": teachers}, default=str))
        print(f"{len(students)} o'quvchi, {len(teachers)} o'qituvchi -> {args.dump}")
        return
    stats: dict[str, list[float]] = defaultdict(list)
    errors: dict[str, int] = defaultdict(int)
    deadline = time.perf_counter() + args.duration
    limits = httpx.Limits(max_connections=args.concurrency, max_keepalive_connections=args.concurrency)

    async with httpx.AsyncClient(base_url=args.base, limits=limits, timeout=30) as c:
        async def worker() -> None:
            while time.perf_counter() < deadline:
                if random.random() < 0.9:
                    u = random.choice(students); name, path = student_request(u)
                else:
                    u = random.choice(teachers); name, path = teacher_request(u)
                t0 = time.perf_counter()
                try:
                    r = await c.get(path, headers=u["h"])
                    ok = r.status_code == 200
                except httpx.HTTPError:
                    ok = False
                stats[name].append((time.perf_counter() - t0) * 1000)
                if not ok:
                    errors[name] += 1

        t_start = time.perf_counter()
        await asyncio.gather(*(worker() for _ in range(args.concurrency)))
        elapsed = time.perf_counter() - t_start

    def pct(xs: list[float], p: float) -> float:
        xs = sorted(xs)
        return xs[min(len(xs) - 1, int(len(xs) * p))]

    total = sum(len(v) for v in stats.values())
    all_ms = [x for v in stats.values() for x in v]
    print(f"\nParallel: {args.concurrency}, vaqt: {elapsed:.0f}s, so'rovlar: {total}, "
          f"tezlik: {total / elapsed:.0f} so'rov/s, xatolar: {sum(errors.values())}")
    print(f"{'endpoint':18s} {'soni':>6s} {'p50':>7s} {'p95':>7s} {'p99':>7s} {'xato':>5s}")
    for name, xs in sorted(stats.items(), key=lambda kv: -statistics.median(kv[1])):
        print(f"{name:18s} {len(xs):6d} {statistics.median(xs):6.0f}ms {pct(xs, .95):6.0f}ms {pct(xs, .99):6.0f}ms {errors[name]:5d}")
    print(f"{'JAMI':18s} {total:6d} {statistics.median(all_ms):6.0f}ms {pct(all_ms, .95):6.0f}ms {pct(all_ms, .99):6.0f}ms")


if __name__ == "__main__":
    asyncio.run(main())
