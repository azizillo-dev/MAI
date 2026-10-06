"""AI tekshiruv sifatini o'lchash uchun daftar sahifalari.

Har bir sahifa: vazifa konteksti (ilovadagidek) + o'quvchining qo'lyozmasi + har bir misolning haqiqiy bahosi.
Qo'lyozma belgilari (render.py):  {surat|maxraj} — kasr,  ^{..} — daraja,  _{..} — pastki indeks,
√{..} — ildiz,  ~~..~~ — chizib tashlangan yozuv.

Kutilgan baholar: correct | partial | incorrect | missing.
"""

from dataclasses import dataclass, field


@dataclass
class Item:
    number: str
    text: str  # vazifa sharti (ilovadagi items[].text)
    answer: str | None  # ustoz/AI tayyorlagan to'g'ri javob; None — AI o'zi yechishi kerak
    lines: list[str]  # o'quvchining yozuvi (bir nechta qator)
    expected: str  # correct | partial | incorrect | missing; "a|b" — ikkalasi ham to'g'ri hisoblanadi


@dataclass
class Page:
    id: str
    title: str
    level: str  # oson | o'rta | murakkab
    subject: str  # math | english
    font: str
    photo: dict = field(default_factory=dict)  # rasm sifati: blur, angle, shadow, noise
    items: list[Item] = field(default_factory=list)
    instructions: str | None = None


def I(number, text, answer, lines, expected="correct"):  # noqa: E743 — qisqa yozish uchun
    return Item(str(number), text, answer, lines if isinstance(lines, list) else [lines], expected)


PAGES: list[Page] = [
    Page("p01", "Kasrlarni qo'shish va ayirish", "oson", "math", "segoepr.ttf",
         {"angle": -1.2, "shadow": 0.15, "blur": 0.3},
         [
             I(1, "2/3 + 3/4", "17/12", "{2|3} + {3|4} = {8|12} + {9|12} = {17|12} = 1{5|12}"),
             I(2, "5/6 - 1/4", "7/12", "{5|6} - {1|4} = {10|12} - {3|12} = {7|12}"),
             I(3, "3/5 + 1/2", "11/10", "{3|5} + {1|2} = {4|7}", "incorrect"),
             I(4, "7/8 · 4/21", "1/6", "{7|8} · {4|21} = {28|168} = {1|6}"),
             I(5, "9/10 : 3/5", "3/2", "{9|10} : {3|5} = {9|10} · {5|3} = {45|30} = {3|2}"),
             I(6, "2 1/3 + 1 3/5", "3 14/15", "2{1|3} + 1{3|5} = {7|3} + {8|5} = {35|15} + {24|15} = {59|15} = 3{14|15}"),
             I(7, "4 - 5/6", "3 1/6", "4 - {5|6} = {24|6} - {5|6} = {19|6} = 3{1|6}"),
             I(8, "3/4 · 2/9 + 1/6", "1/3", "{3|4} · {2|9} + {1|6} = {6|36} + {1|6} = {7|42}", "incorrect"),
         ]),
    Page("p02", "Chiziqli tenglamalar", "o'rta", "math", "Inkfree.ttf",
         {"angle": 2.4, "shadow": 0.3, "blur": 0.6, "noise": 10},
         [
             I(1, "3x + 7 = 22", "x = 5", ["3x + 7 = 22", "3x = 15", "x = 5"]),
             I(2, "5x - 3 = 2x + 9", "x = 4", ["5x - 3 = 2x + 9", "3x = 12", "x = 4"]),
             I(3, "2(x - 4) = 3x + 1", "x = -9", ["2x - 8 = 3x + 1", "-x = 9", "x = -9"]),
             I(4, "7 - 2x = 3(x - 1)", "x = 2", ["7 - 2x = 3x - 1", "-5x = -8", "x = 1,6"], "incorrect"),
             I(5, "x/3 + x/4 = 7", "x = 12", ["{x|3} + {x|4} = 7", "4x + 3x = 84", "7x = 84,  x = 12"]),
             I(6, "0,4x - 1,2 = 0,2x + 0,6", "x = 9", ["0,4x - 0,2x = 0,6 + 1,2", "0,2x = 1,8", "x = 9"]),
             I(7, "4(2x + 1) - 3(x - 2) = 25", "x = 3", ["8x + 4 - 3x - 6 = 25", "5x = 27", "x = 5,4"], "incorrect"),
             I(8, "(2x - 1)/5 = (x + 4)/3", "x = 23", ["{2x - 1|5} = {x + 4|3}", "6x - 3 = 5x + 20", "x = 23"]),
         ]),
    Page("p03", "Darajalar va ildizlar", "o'rta", "math", "comic.ttf",
         {"angle": -0.8, "shadow": 0.2, "blur": 0.4},
         [
             I(1, "2^3 · 2^4", "128", "2^{3} · 2^{4} = 2^{7} = 128"),
             I(2, "(3^2)^3", "729", "(3^{2})^{3} = 3^{6} = 729"),
             I(3, "√12 ni soddalashtiring", "2√3", "√{12} = √{4 · 3} = 2√{3}"),
             I(4, "√50 + √18", "8√2", "√{50} + √{18} = 5√{2} + 3√{2} = 8√{2}"),
             I(5, "√2 · √8", "4", "√{2} · √{8} = √{16} = 4"),
             I(6, "(a^3 b^2)^2 : (a^4 b)", "a^2 b^3", "(a^{3}b^{2})^{2} : a^{4}b = a^{6}b^{4} : a^{4}b = a^{2}b^{4}", "incorrect"),
             I(7, "5^(-2)", "0,04", "5^{-2} = {1|5^{2}} = {1|25}"),
             I(8, "√18 / √2", "3", "{√{18}|√{2}} = √{9} = 3"),
             I(9, "√(9 + 16)", "5", "√{9 + 16} = 3 + 4 = 7", "incorrect"),
         ]),
    Page("p04", "Kvadrat tenglamalar", "murakkab", "math", "segoesc.ttf",
         {"angle": 1.5, "shadow": 0.25, "blur": 0.5},
         [
             I(1, "x^2 - 5x + 6 = 0", "x = 2; x = 3", ["x^{2} - 5x + 6 = 0", "D = 25 - 24 = 1", "x_{1} = 3,  x_{2} = 2"]),
             I(2, "x^2 + 2x - 15 = 0", "x = 3; x = -5", ["D = 4 + 60 = 64", "x = {-2 ± 8|2}", "x_{1} = 3,  x_{2} = -5"]),
             I(3, "2x^2 - 7x + 3 = 0", "x = 3; x = 1/2", ["D = 49 - 24 = 25", "x = {7 ± 5|4}", "x_{1} = 3,  x_{2} = 0,5"]),
             I(4, "x^2 - 9 = 0", "x = ±3", ["x^{2} = 9", "x = 3"], "partial|incorrect"),
             I(5, "x^2 + 4x + 5 = 0", "ildizi yo'q", ["D = 16 - 20 = -4 < 0", "haqiqiy ildizi yo'q"]),
             I(6, "3x^2 - 12x = 0", "x = 0; x = 4", ["3x(x + 4) = 0", "x = 0,  x = -4"], "incorrect|partial"),
             I(7, "x^2 - 6x + 9 = 0", "x = 3", ["(x - 3)^{2} = 0", "x = 3"]),
         ]),
    Page("p05", "Tengsizliklar va tenglamalar sistemasi", "murakkab", "math", "Inkfree.ttf",
         {"angle": -2.0, "shadow": 0.35, "blur": 0.9, "noise": 12},
         [
             I(1, "3x - 5 > 7", "x > 4", ["3x > 12", "x > 4"]),
             I(2, "-2x + 3 ≤ 11", "x ≥ -4", ["-2x ≤ 8", "x ≤ -4"], "incorrect"),
             I(3, "x + y = 7; x - y = 1", "x = 4; y = 3", ["2x = 8,  x = 4", "y = 7 - 4 = 3"]),
             I(4, "2x + 3y = 12; x - y = 1", "x = 3; y = 2", ["x = y + 1", "2y + 2 + 3y = 12", "5y = 10,  y = 2,  x = 3"]),
             I(5, "x^2 - 4 < 0", "-2 < x < 2", ["x^{2} < 4", "x ∈ (-2; 2)"]),
             I(6, "y = x^2; y = 2x + 3", "(3; 9) va (-1; 1)", ["x^{2} = 2x + 3", "x^{2} - 2x - 3 = 0", "x = 3,  y = 9", "Javob: (3; 9)"], "partial|incorrect"),
         ]),
    Page("p06", "Logarifm va trigonometriya", "murakkab", "math", "BRADHITC.TTF",
         {"angle": 1.0, "shadow": 0.2, "blur": 0.5},
         [
             I(1, "log_2 32", None, "log_{2} 32 = 5"),
             I(2, "log_3 81 - log_3 9", None, "log_{3} 81 - log_{3} 9 = log_{3} 9 = 2"),
             I(3, "lg 25 + lg 4", None, "lg 25 + lg 4 = lg 100 = 2"),
             I(4, "log_2 (x - 1) = 3 tenglamani yeching", None, ["x - 1 = 2^{3} = 8", "x = 9"]),
             I(5, "log_2 8 + log_2 4", None, "log_{2} 8 + log_{2} 4 = log_{2} 12", "incorrect"),
             I(6, "sin 30° + cos 60°", None, "sin 30° + cos 60° = {1|2} + {1|2} = 1"),
             I(7, "sin^2 α + cos^2 α - tg α · ctg α", None, "sin^{2}α + cos^{2}α - tgα · ctgα = 1 - 1 = 0"),
             I(8, "cos 120°", None, "cos 120° = {1|2}", "incorrect"),
             I(9, "2 sin x = 1 tenglamaning [0; π] oraliqdagi yechimlari", None,
               ["sin x = {1|2}", "x = {π|6},  x = {5π|6}"]),
         ]),
    Page("p07", "Hosila va integral", "murakkab", "math", "segoepr.ttf",
         {"angle": -1.6, "shadow": 0.45, "blur": 1.1, "noise": 14, "dark": 0.18},
         [
             I(1, "(x^3 - 4x + 1)'", None, "(x^{3} - 4x + 1)' = 3x^{2} - 4"),
             I(2, "(sin 2x)'", None, "(sin 2x)' = cos 2x", "incorrect"),
             I(3, "(x · e^x)'", None, "(x · e^{x})' = e^{x} + x · e^{x}"),
             I(4, "(ln(x^2 + 1))'", None, "(ln(x^{2} + 1))' = {2x|x^{2} + 1}"),
             I(5, "∫ (3x^2 + 2x) dx", None, "∫(3x^{2} + 2x)dx = x^{3} + x^{2} + C"),
             I(6, "0 dan 2 gacha ∫ x dx", None, "∫_{0}^{2} x dx = {x^{2}|2} = 2"),
             I(7, "1 dan 3 gacha ∫ (2x + 1) dx", None, ["∫_{1}^{3}(2x + 1)dx = (x^{2} + x) |", "= 12 - 2 = 10"]),
             I(8, "f(x) = x^2 - 4x funksiyaning kritik nuqtasi", None, ["f'(x) = 2x - 4 = 0", "x = 2"]),
         ]),
    Page("p08", "Matnli masalalar", "o'rta", "math", "comic.ttf",
         {"angle": 0.6, "shadow": 0.2, "blur": 0.4},
         [
             I(1, "5 ta daftar 12 000 so'm turadi. 8 ta daftar necha so'm turadi?", None,
               ["12 000 : 5 = 2 400 so'm", "2 400 · 8 = 19 200 so'm", "Javob: 19 200 so'm"]),
             I(2, "Mahsulot narxi 80 000 so'm. 15% chegirmadan keyin narxi qancha?", None,
               ["80 000 · 0,15 = 12 000", "80 000 - 12 000 = 68 000", "Javob: 68 000 so'm"]),
             I(3, "Poyezd 3 soatda 240 km yurdi. Shu tezlikda 5 soatda necha km yuradi?", None,
               ["240 : 3 = 80 km/soat", "80 · 5 = 400 km", "Javob: 400 km"]),
             I(4, "Sinfda 30 o'quvchi bor, ularning 40% i qizlar. Sinfda nechta o'g'il bola bor?", None,
               ["30 · 0,4 = 12", "Javob: 12 ta"], "incorrect"),
             I(5, "Ikki sonning yig'indisi 45, ayirmasi 7. Shu sonlarni toping.", None,
               ["(45 + 7) : 2 = 26", "45 - 26 = 19", "Javob: 26 va 19"]),
         ]),
    Page("p09", "Present Simple va Past Simple", "oson", "english", "Inkfree.ttf",
         {"angle": 1.8, "shadow": 0.25, "blur": 0.6},
         [
             I(1, "She ___ (go) to school every day.", "goes", "She goes to school every day."),
             I(2, "They ___ (play) football yesterday.", "played", "They played football yesterday."),
             I(3, "He ___ (not / like) coffee.", "doesn't like", "He don't like coffee.", "incorrect"),
             I(4, "I ___ (see) a film last night.", "saw", "I saw a film last night."),
             I(5, "We ___ (be) at home now.", "are", "We are at home now."),
             I(6, "My father ___ (buy) a car in 2020.", "bought", "My father buyed a car in 2020.", "incorrect"),
             I(7, "___ you ___ (speak) English?", "Do ... speak", "Do you speak English?"),
             I(8, "The sun ___ (rise) in the east.", "rises", "The sun rises in the east."),
         ], instructions="Qavs ichidagi fe'lni to'g'ri shaklda yozing."),
    Page("p10", "Amallar tartibi", "murakkab", "math", "Inkfree.ttf",
         {"angle": 5.5, "shadow": 0.55, "blur": 1.6, "noise": 18, "dark": 0.25},
         [
             I(1, "15 - 3 · 4", "3", "15 - 3 · 4 = 15 - 12 = 3"),
             I(2, "(-3)^2 - 2^3", "1", "(-3)^{2} - 2^{3} = ~~-17~~ 9 - 8 = 1"),
             I(3, "1/2 + 1/3 · 6", "2 1/2", "{1|2} + {1|3} · 6 = {1|2} + 2 = 2{1|2}"),
             I(4, "|-7| - |3 - 10|", "0", "|-7| - |3 - 10| = 7 - 7 = 0"),
             I(5, "2^5 : 2^3", "4", [], "missing"),
             I(6, "0,25 · 1,6", "0,4", "0,25 · 1,6 = ~~0,04~~ 0,4"),
             I(7, "48 : (-6) + 12", "4", "48 : (-6) + 12 = -8 + 12 = 4"),
             I(8, "3 - 2 · (5 - 7)", "7", "3 - 2 · (-2) = 1 · (-2) = -2", "incorrect"),
         ]),
]
