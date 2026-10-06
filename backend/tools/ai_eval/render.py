"""Daftar sahifasini "telefon surati"ga o'xshatib chizadi (qo'lyozma shrift, kasr, daraja, ildiz, chizib tashlash).

Rasm ilovadagidek tayyorlanadi: eng uzun tomoni 2200 px, JPEG 82%.
"""

import io
import random
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from tools.ai_eval.cases import Page

FONTS_DIR = Path("C:/Windows/Fonts") if Path("C:/Windows/Fonts").exists() else Path("/usr/share/fonts")
# Shriftda yo'q belgilar boshqa shriftdan olinadi
MISSING = {
    "Inkfree.ttf": set("√≤≥≠∫−∞∈∅→±"),
    "comic.ttf": set("∈∅→"),
    "BRADHITC.TTF": set("αβ∈∅→"),
    "segoepr.ttf": set("∈∅"),
    "segoesc.ttf": set("∈∅"),
}
FALLBACK = "segoepr.ttf"
SYMBOLS = "seguisym.ttf"

PAGE_W, PAGE_H = 1500, 2120
LINE_H = 70
MARGIN_X = 170


@lru_cache(maxsize=256)
def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS_DIR / name), size)


# ---------------------------------------------------------------- Belgilash tili -> daraxt


def _braced(s: str, i: int) -> tuple[str, int]:
    """s[i] == '{' — mos '}' gacha bo'lgan ichki qism va keyingi indeks."""
    depth, j = 0, i
    while j < len(s):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return s[i + 1:j], j + 1
        j += 1
    raise ValueError(f"Yopilmagan qavs: {s}")


def _split_top(s: str, sep: str) -> list[str]:
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def parse(s: str) -> list:
    nodes, buf, i = [], "", 0

    def flush():
        nonlocal buf
        if buf:
            nodes.append(("t", buf))
            buf = ""

    while i < len(s):
        if s.startswith("~~", i):
            end = s.index("~~", i + 2)
            flush()
            nodes.append(("strike", parse(s[i + 2:end])))
            i = end + 2
        elif s[i] in "^_" and i + 1 < len(s) and s[i + 1] == "{":
            inner, i2 = _braced(s, i + 1)
            flush()
            nodes.append(("sup" if s[i] == "^" else "sub", parse(inner)))
            i = i2
        elif s[i] == "√" and i + 1 < len(s) and s[i + 1] == "{":
            inner, i2 = _braced(s, i + 1)
            flush()
            nodes.append(("sqrt", parse(inner)))
            i = i2
        elif s[i] == "{":
            inner, i2 = _braced(s, i)
            flush()
            num, den = _split_top(inner, "|")
            nodes.append(("frac", parse(num), parse(den)))
            i = i2
        else:
            buf += s[i]
            i += 1
    flush()
    return nodes


# ---------------------------------------------------------------- O'lchash va chizish


@dataclass
class Pen:
    draw: ImageDraw.ImageDraw
    fname: str
    ink: tuple[int, int, int]
    rnd: random.Random

    def glyph_font(self, ch: str, size: int) -> ImageFont.FreeTypeFont:
        if ch in MISSING.get(self.fname, set()):
            return font(SYMBOLS if ch in "∈∅" else FALLBACK, size)
        return font(self.fname, size)

    def text_width(self, text: str, size: int) -> float:
        return sum(self.glyph_font(ch, size).getlength(ch) for ch in text)

    def measure(self, nodes: list, size: int) -> tuple[float, float, float]:
        """(kenglik, baseline'dan yuqori, baseline'dan past)."""
        w, up, down = 0.0, size * 0.75, size * 0.25
        for n in nodes:
            if n[0] == "t":
                w += self.text_width(n[1], size)
            elif n[0] in ("sup", "sub"):
                sw, su, sd = self.measure(n[1], int(size * 0.62))
                w += sw + 2
                if n[0] == "sup":
                    up = max(up, size * 0.45 + su)
                else:
                    down = max(down, size * 0.2 + sd)
            elif n[0] == "sqrt":
                sw, su, sd = self.measure(n[1], size)
                w += sw + size * 0.55
                up = max(up, su + 8)
                down = max(down, sd)
            elif n[0] == "frac":
                fs = int(size * 0.78)
                nw, nu, nd = self.measure(n[1], fs)
                dw, du, dd = self.measure(n[2], fs)
                w += max(nw, dw) + 12
                up = max(up, size * 0.32 + 6 + nu + nd)
                down = max(down, -size * 0.32 + 6 + du + dd)
            elif n[0] == "strike":
                sw, su, sd = self.measure(n[1], size)
                w += sw
        return w, up, down

    def render(self, nodes: list, x: float, base: float, size: int) -> float:
        for n in nodes:
            kind = n[0]
            if kind == "t":
                for ch in n[1]:
                    s = max(8, int(size * self.rnd.uniform(0.96, 1.04)))
                    f = self.glyph_font(ch, s)
                    jitter = self.rnd.uniform(-1.6, 1.6)
                    self.draw.text((x, base + jitter), ch, font=f, fill=self.ink, anchor="ls")
                    x += f.getlength(ch) * self.rnd.uniform(0.97, 1.03)
            elif kind in ("sup", "sub"):
                s = int(size * 0.62)
                dy = -size * 0.45 if kind == "sup" else size * 0.2
                x = self.render(n[1], x + 1, base + dy, s) + 1
            elif kind == "sqrt":
                w, up, _ = self.measure(n[1], size)
                top = base - up - 2
                pts = [(x, base - size * 0.3), (x + size * 0.12, base - size * 0.38), (x + size * 0.25, base + 4),
                       (x + size * 0.45, top), (x + size * 0.55 + w + 4, top + self.rnd.uniform(-2, 2))]
                self.draw.line(pts, fill=self.ink, width=3, joint="curve")
                x = self.render(n[1], x + size * 0.55, base, size) + 4
            elif kind == "frac":
                fs = int(size * 0.78)
                nw, _, nd = self.measure(n[1], fs)
                dw, du, _ = self.measure(n[2], fs)
                fw = max(nw, dw) + 8
                bar = base - size * 0.32
                self.draw.line([(x + 2, bar), (x + fw + 2, bar + self.rnd.uniform(-2, 2))], fill=self.ink, width=3)
                self.render(n[1], x + 4 + (fw - nw) / 2, bar - 6 - nd, fs)
                self.render(n[2], x + 4 + (fw - dw) / 2, bar + 6 + du, fs)
                x += fw + 12
            elif kind == "strike":
                x0 = x
                x = self.render(n[1], x, base, size)
                for k in range(3):  # qo'lda chizib tashlangandek
                    y = base - size * 0.3 + k * 4 - 4
                    self.draw.line([(x0 - 3, y + self.rnd.uniform(-3, 3)), (x + 3, y + self.rnd.uniform(-3, 3))],
                                   fill=self.ink, width=3)
        return x


# ---------------------------------------------------------------- Sahifa va "surat"


def _paper(rnd: random.Random) -> Image.Image:
    img = Image.new("RGB", (PAGE_W, PAGE_H), (248, 246, 238))
    d = ImageDraw.Draw(img)
    for y in range(190, PAGE_H - 40, LINE_H):
        d.line([(0, y), (PAGE_W, y)], fill=(170, 195, 230), width=2)
    d.line([(MARGIN_X - 30, 0), (MARGIN_X - 30, PAGE_H)], fill=(225, 120, 120), width=3)
    return img


def draw_page(page: Page, seed: int = 7, date: str = "28.09.2026") -> Image.Image:
    rnd = random.Random(f"{page.id}-{seed}")
    img = _paper(rnd)
    ink = (rnd.randint(15, 35), rnd.randint(35, 60), rnd.randint(120, 160))
    pen = Pen(ImageDraw.Draw(img), page.font, ink, rnd)
    size = 44 if page.font in ("segoesc.ttf", "BRADHITC.TTF") else 40

    y = 190 - 12
    pen.render(parse(f"{date}        Uy ishi: {page.title}"), MARGIN_X, y, size)
    y += LINE_H * 2
    for item in page.items:
        if not item.lines:  # o'quvchi bu misolni tashlab ketgan
            continue
        pen.render(parse(f"{item.number})"), MARGIN_X - 10 + rnd.uniform(-4, 4), y, size)
        for line in item.lines:
            nodes = parse(line)
            _, up, down = pen.measure(nodes, size)
            # Kasr baland bo'lsa qator ko'proq joy egallaydi (daftarda ham ikki qatorga yoziladi)
            if up > LINE_H * 0.8:
                y += LINE_H // 2
            pen.render(nodes, MARGIN_X + 60 + rnd.uniform(-6, 6), y, size)
            y += LINE_H + (LINE_H // 2 if down > LINE_H * 0.45 else 0)
        y += LINE_H // 2
        if y > PAGE_H - LINE_H:
            break
    return img


def to_photo(img: Image.Image, photo: dict, seed: int = 7) -> Image.Image:
    rnd = random.Random(seed)
    # Stol ustidagi daftar: atrofida qorong'i hoshiya
    table = Image.new("RGB", (img.width + 160, img.height + 160), (70, 58, 50))
    table.paste(img, (80, 80))
    img = table.rotate(photo.get("angle", 0), resample=Image.BICUBIC, expand=False, fillcolor=(70, 58, 50))

    # Yengil perspektiva (telefon biroz qiya tutilgan)
    w, h = img.size
    k = 0.012
    quad = (rnd.uniform(0, w * k), rnd.uniform(0, h * k), rnd.uniform(0, w * k), h - rnd.uniform(0, h * k),
            w - rnd.uniform(0, w * k), h - rnd.uniform(0, h * k), w - rnd.uniform(0, w * k), rnd.uniform(0, h * k))
    img = img.transform((w, h), Image.QUAD, quad, resample=Image.BICUBIC)

    # Soya: bir burchakdan qoraygan yorug'lik
    if photo.get("shadow"):
        grad = Image.linear_gradient("L").resize((w, h)).rotate(rnd.choice([30, 120, 210, 300]), expand=False)
        shade = grad.point(lambda v: int(255 - v * photo["shadow"]))
        img = ImageChops.multiply(img, Image.merge("RGB", (shade, shade, shade)))
    if photo.get("dark"):
        img = img.point(lambda v: int(v * (1 - photo["dark"])))
    if photo.get("blur"):
        img = img.filter(ImageFilter.GaussianBlur(photo["blur"]))
    if photo.get("noise"):
        noise = Image.effect_noise((w, h), photo["noise"]).convert("RGB")
        img = ImageChops.add(img, noise, scale=1.0, offset=-128)

    img.thumbnail((2200, 2200), Image.LANCZOS)
    return img


def jpeg(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=82)
    return buf.getvalue()


def page_photo(page: Page) -> bytes:
    seed = sum(map(ord, page.id))  # hash() har ishga tushishda o'zgaradi — rasm barqaror bo'lsin
    return jpeg(to_photo(draw_page(page), page.photo, seed=seed))


if __name__ == "__main__":
    import sys

    from tools.ai_eval.cases import PAGES

    out = Path(sys.argv[1] if len(sys.argv) > 1 else "ai_eval_pages")
    out.mkdir(parents=True, exist_ok=True)
    for p in PAGES:
        data = page_photo(p)
        (out / f"{p.id}.jpg").write_bytes(data)
        print(p.id, len(data) // 1024, "KB")
