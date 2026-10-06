"""AI tekshiruvni turli modellarda solishtirish.

    python -m tools.ai_eval.run --out <papka> [--runs 2] [--configs a,b] [--report-only]

Ilovadagi aynan o'sha ko'rsatma (GRADE_SYSTEM), kontekst va javob sxemasi (GradeResult) ishlatiladi.
Natija: <out>/results.jsonl (xom javoblar) va <out>/report.md (jadvallar).
"""

import argparse
import asyncio
import json
import re
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.ai import prompts
from app.ai.provider import GradingContext
from app.ai.schemas import GradeResult
from tools.ai_eval.cases import PAGES, Page

USD_UZS = 12700


@dataclass
class Config:
    key: str
    label: str
    model: str
    thinking: int  # -1 — dinamik (ilovadagidek), 0 — o'chiq, N — chegara
    price_in: float  # $ / 1 mln token
    price_out: float


CONFIGS = [
    Config("flash36", "gemini-3.6-flash (hozirgi)", "gemini-3.6-flash", -1, 0.75, 3.75),
    Config("flash36_t1k", "gemini-3.6-flash, fikrlash ≤1024", "gemini-3.6-flash", 1024, 0.75, 3.75),
    Config("lite35", "gemini-3.5-flash-lite", "gemini-3.5-flash-lite", -1, 0.30, 2.50),
    Config("lite31", "gemini-3.1-flash-lite", "gemini-3.1-flash-lite", -1, 0.25, 1.50),
    # gemini-2.5-flash-lite ($0.10 / $0.40) — 2026-09 holatiga yangi foydalanuvchilarga yopilgan (404)
]

TEACHER = ("7–11-sinflarga matematika va ingliz tilidan dars beraman. Baholashda yechim yo'lini ham ko'raman, "
           "lekin to'g'ri javobning boshqacha, teng kuchli yozilishini to'g'ri deb hisoblayman.")


def context(page: Page) -> GradingContext:
    return GradingContext(
        teacher_context=TEACHER, subject=page.subject, grading_scale="5", title=page.title,
        instructions=page.instructions,
        items=[{"number": i.number, "text": i.text, "answer": i.answer} for i in page.items],
        feedback_language="uz",
    )


async def grade_once(client, cfg: Config, page: Page, image: bytes) -> dict:
    from google.genai import errors, types

    ctx = context(page)
    config = types.GenerateContentConfig(
        system_instruction=prompts.GRADE_SYSTEM + "\n\n" + prompts.grading_context(ctx),
        response_mime_type="application/json",
        response_schema=GradeResult,
        temperature=0.2,
        max_output_tokens=16000,
        thinking_config=types.ThinkingConfig(thinking_budget=cfg.thinking),
    )
    parts = [types.Part.from_bytes(data=image, mime_type="image/jpeg"), prompts.grade_request(None, 1)]
    last = None
    for attempt in range(6):
        started = time.monotonic()
        try:
            r = await client.aio.models.generate_content(model=cfg.model, contents=parts, config=config)
            u = r.usage_metadata
            parsed = r.parsed if isinstance(r.parsed, GradeResult) else None
            return {
                "ok": parsed is not None,
                "error": None if parsed else f"parse ({r.candidates[0].finish_reason if r.candidates else '?'})",
                "latency": time.monotonic() - started,
                "in": u.prompt_token_count or 0, "out": u.candidates_token_count or 0,
                "think": u.thoughts_token_count or 0,
                "result": parsed.model_dump() if parsed else None,
            }
        except (errors.ServerError, errors.ClientError, httpx.HTTPError) as exc:
            last = exc
            retry = isinstance(exc, httpx.HTTPError) or getattr(exc, "code", None) in (429, 500, 503)
            if retry and attempt < 5:  # tarmoq uzilishi yoki limit — kutib qayta urinamiz
                await asyncio.sleep(5 * 2 ** attempt)
                continue
            break
    return {"ok": False, "error": str(last)[:200], "latency": 0, "in": 0, "out": 0, "think": 0, "result": None}


def load_images(out: Path) -> dict[str, bytes]:
    """Rasmlar bir marta chiziladi va <out>/pages ga saqlanadi (serverda qo'lyozma shriftlari yo'q —
    rasmlarni kompyuterda tayyorlab, papkani ko'chirish kifoya)."""
    pages_dir = out / "pages"
    missing = [p for p in PAGES if not (pages_dir / f"{p.id}.jpg").exists()]
    if missing:
        from tools.ai_eval.render import page_photo

        pages_dir.mkdir(parents=True, exist_ok=True)
        for p in missing:
            (pages_dir / f"{p.id}.jpg").write_bytes(page_photo(p))
    return {p.id: (pages_dir / f"{p.id}.jpg").read_bytes() for p in PAGES}


async def run(out: Path, runs: int, keys: list[str], concurrency: int, delay: float) -> None:
    import os

    from google import genai

    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        from dotenv import dotenv_values

        key = dotenv_values(".env")["GEMINI_API_KEY"]
    client = genai.Client(api_key=key)
    images = load_images(out)

    path = out / "results.jsonl"
    done = set()
    if path.exists():  # to'xtab qolsa, qolgan joyidan davom etadi
        for line in path.read_text(encoding="utf-8").splitlines():
            d = json.loads(line)
            if d["ok"]:
                done.add((d["config"], d["page"], d["run"]))

    sem = asyncio.Semaphore(concurrency)
    lock = asyncio.Lock()
    cfgs = [c for c in CONFIGS if c.key in keys]
    jobs = [(c, p, r) for r in range(runs) for c in cfgs for p in PAGES if (c.key, p.id, r) not in done]
    print(f"{len(jobs)} ta tekshiruv ({len(done)} tasi avval bajarilgan)", flush=True)

    async def job(cfg, page, r):
        async with sem:
            res = await grade_once(client, cfg, page, images[page.id])
            await asyncio.sleep(delay)  # daqiqalik limitdan oshmaslik uchun (kalit ilova bilan umumiy)
        res.update(config=cfg.key, page=page.id, run=r)
        async with lock:
            with path.open("a", encoding="utf-8") as f:
                f.write(json.dumps(res, ensure_ascii=False) + "\n")
        status = "ok" if res["ok"] else f"XATO {res['error']}"
        print(f"{cfg.key:12} {page.id} run{r}  {res['latency']:5.1f}s  {status}", flush=True)

    await asyncio.gather(*(job(*j) for j in jobs))


# ---------------------------------------------------------------- Hisobot

VALUE = {"correct": 1.0, "partial": 0.5, "incorrect": 0.0, "missing": 0.0}


def _num(s: str) -> str:
    m = re.search(r"\d+[a-z]?", str(s).lower())
    return m.group(0) if m else str(s).strip()


def evaluate(page: Page, result: dict | None) -> list[dict]:
    got = {}
    for it in (result or {}).get("items", []):
        got.setdefault(_num(it["number"]), it)
    rows = []
    for item in page.items:
        exp = set(item.expected.split("|"))
        g = got.get(_num(item.number))
        pred = g["verdict"] if g else "absent"
        rows.append({
            "number": item.number, "text": item.text, "expected": item.expected, "pred": pred,
            "comment": (g or {}).get("comment", ""),
            "exact": pred in exp,
            "fn": exp == {"correct"} and pred != "correct",  # to'g'ri javobni xato deb qo'ydi
            "fp": "correct" not in exp and pred == "correct",  # xatoni o'tkazib yubordi
        })
    return rows


def expected_score(page: Page) -> tuple[float, float]:
    lo = sum(min(VALUE[e] for e in i.expected.split("|")) for i in page.items)
    hi = sum(max(VALUE[e] for e in i.expected.split("|")) for i in page.items)
    n = len(page.items)
    return lo / n * 100, hi / n * 100


def report(out: Path) -> str:
    pages = {p.id: p for p in PAGES}
    cfgs = {c.key: c for c in CONFIGS}
    data = [json.loads(line) for line in (out / "results.jsonl").read_text(encoding="utf-8").splitlines()]
    # Har bir (config, page, run) uchun oxirgi muvaffaqiyatli natija
    latest = {}
    for d in data:
        if d["ok"] or (d["config"], d["page"], d["run"]) not in latest:
            latest[(d["config"], d["page"], d["run"])] = d

    agg = defaultdict(lambda: defaultdict(float))
    by_level = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    mistakes = defaultdict(list)
    preds = defaultdict(dict)
    for (ck, pid, r), d in sorted(latest.items()):
        a = agg[ck]
        a["calls"] += 1
        if not d["ok"]:
            a["failed"] += 1
            continue
        c, page = cfgs[ck], pages[pid]
        rows = evaluate(page, d["result"])
        a["items"] += len(rows)
        a["exact"] += sum(x["exact"] for x in rows)
        a["fn"] += sum(x["fn"] for x in rows)
        a["fp"] += sum(x["fp"] for x in rows)
        a["n_correct"] += sum(set(i.expected.split("|")) == {"correct"} for i in page.items)
        a["n_wrong"] += sum("correct" not in i.expected.split("|") for i in page.items)
        lo, hi = expected_score(page)
        sp = d["result"]["score_percent"]
        a["score_err"] += 0 if lo <= sp <= hi else min(abs(sp - lo), abs(sp - hi))
        a["ok_calls"] += 1
        a["latency"] += d["latency"]
        a["in"] += d["in"]
        a["out"] += d["out"] + d["think"]
        a["think"] += d["think"]
        a["cost"] += (d["in"] * c.price_in + (d["out"] + d["think"]) * c.price_out) / 1e6
        a["conf"] += d["result"]["confidence"]
        lvl = by_level[ck][page.level]
        lvl[0] += sum(x["exact"] for x in rows)
        lvl[1] += len(rows)
        for x in rows:
            preds[(ck, pid, x["number"])][r] = x["pred"]
            if not x["exact"]:
                mistakes[ck].append((pid, r, x))

    lines = ["# AI tekshiruv: modellarni solishtirish", "",
             f"{len(PAGES)} ta daftar sahifasi, {sum(len(p.items) for p in PAGES)} ta misol "
             f"(oson/o'rta/murakkab, qo'lyozma, xira va qiyshiq suratlar). Narx: 1 $ = {USD_UZS} so'm.", "",
             "| Model | Aniq baho | To'g'rini xato dedi | Xatoni o'tkazdi | Baho foizi xatosi | "
             "Barqarorlik | 1 tekshiruv | Vaqt | Tokenlar (kirish / chiqish) | Muvaffaqiyatsiz |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for ck, a in agg.items():
        if not a["ok_calls"]:
            lines.append(f"| {cfgs[ck].label} | — | — | — | — | — | — | — | — | {int(a['failed'])}/{int(a['calls'])} |")
            continue
        n = a["ok_calls"]
        # Barqarorlik: ikki ishga tushirishda bir xil baho berilgan misollar ulushi
        same = total = 0
        for (k, _, _), rs in preds.items():
            if k == ck and len(rs) > 1:
                total += 1
                same += len(set(rs.values())) == 1
        stab = f"{same / total:.0%}" if total else "—"
        cost = a["cost"] / n
        lines.append(
            f"| {cfgs[ck].label} | **{a['exact'] / a['items']:.1%}** | {int(a['fn'])} / {int(a['n_correct'])} "
            f"({a['fn'] / max(1, a['n_correct']):.1%}) | {int(a['fp'])} / {int(a['n_wrong'])} "
            f"({a['fp'] / max(1, a['n_wrong']):.1%}) | {a['score_err'] / n:.1f} p.p. | {stab} | "
            f"${cost:.4f} ({cost * USD_UZS:.0f} so'm) | {a['latency'] / n:.0f} s | "
            f"{a['in'] / n:.0f} / {a['out'] / n:.0f} | {int(a['failed'])}/{int(a['calls'])} |")

    lines += ["", "## Daraja bo'yicha aniqlik", "", "| Model | Oson | O'rta | Murakkab |", "|---|---|---|---|"]
    for ck in agg:
        lv = by_level[ck]
        cells = [f"{lv[k][0] / lv[k][1]:.0%}" if lv[k][1] else "—" for k in ("oson", "o'rta", "murakkab")]
        lines.append(f"| {cfgs[ck].label} | " + " | ".join(cells) + " |")

    lines += ["", "## Xatolar ro'yxati", ""]
    for ck, ms in mistakes.items():
        lines.append(f"### {cfgs[ck].label} — {len(ms)} ta")
        for pid, r, x in ms:
            lines.append(f"- {pid} №{x['number']} (run{r}) `{x['text']}` — kutilgan **{x['expected']}**, "
                         f"berdi **{x['pred']}**. {x['comment'][:160]}")
        lines.append("")
    text = "\n".join(lines)
    (out / "report.md").write_text(text, encoding="utf-8")
    return text


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--configs", default=",".join(c.key for c in CONFIGS))
    ap.add_argument("--concurrency", type=int, default=1)
    ap.add_argument("--delay", type=float, default=20, help="har bir so'rovdan keyin kutish, soniya")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    if not a.report_only:
        asyncio.run(run(out, a.runs, a.configs.split(","), a.concurrency, a.delay))
    print(report(out))


if __name__ == "__main__":
    main()
