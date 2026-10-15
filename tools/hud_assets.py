"""Собирает HUD-подложки из исходных картинок в content/panorama/images/custom_game/hud.

Исходники (рисованные) не меняются; скрипт пишет *_hud.png / *_shadow.png:
растягивает рамки только по гладким участкам (углы и камни не искажаются),
запекает тень по контуру (box-shadow в Panorama только прямоугольный).
Зоны растяжения подобраны вручную под текущие картинки — после замены
исходника их нужно подобрать заново. Запуск: python tools/hud_assets.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HUD = os.path.join(
    os.path.dirname(__file__), "..", "content", "panorama", "images", "custom_game", "hud"
)


def load(name, crop=True):
    img = Image.open(os.path.join(HUD, name)).convert("RGBA")
    if crop:
        img = img.crop(img.getchannel("A").point(lambda a: 255 if a > 25 else 0).getbbox())
    return np.asarray(img, np.float64) / 255


def save(name, img):
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(HUD, name))
    print(name, img.shape[1], "x", img.shape[0])


def axis_map(n_src, zones, n_out, scale):
    """Координата в исходнике для каждого выходного пикселя: зоны тянутся/сжимаются
    поровну, остальное масштабируется на scale. Без зон — равномерно."""
    if not zones:
        return (np.arange(n_out) + 0.5) * n_src / n_out - 0.5
    zone_len = sum(b - a for a, b in zones)
    zone_out = (n_out - (n_src - zone_len) * scale) / len(zones)
    assert zone_out > 0, "зоны не помещаются"
    src, out = [0.0], [0.0]
    for a, b in zones:
        out.append(out[-1] + (a - src[-1]) * scale)
        src.append(a)
        out.append(out[-1] + zone_out)
        src.append(b)
    out.append(out[-1] + (n_src - src[-1]) * scale)
    src.append(n_src)
    return np.interp(np.arange(n_out) + 0.5, out, src) - 0.5


def stretch(img, size, scale, xzones=(), yzones=()):
    """size — (w, h) результата; scale — масштаб нерастягиваемых частей."""
    w, h = size

    ys = axis_map(img.shape[0], yzones, h, scale)
    xs = axis_map(img.shape[1], xzones, w, scale)
    # билинейная выборка по premultiplied, чтобы прозрачные пиксели не давали кайму
    p = img.copy()
    p[:, :, :3] *= p[:, :, 3:]
    y0 = np.clip(np.floor(ys).astype(int), 0, img.shape[0] - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, img.shape[1] - 1)
    y1 = np.clip(y0 + 1, 0, img.shape[0] - 1)
    x1 = np.clip(x0 + 1, 0, img.shape[1] - 1)
    fy = np.clip(ys - y0, 0, 1)[:, None, None]
    fx = np.clip(xs - x0, 0, 1)[None, :, None]
    o = (p[y0][:, x0] * (1 - fx) + p[y0][:, x1] * fx) * (1 - fy) + (
        p[y1][:, x0] * (1 - fx) + p[y1][:, x1] * fx
    ) * fy
    a = o[:, :, 3:]
    o[:, :, :3] = np.where(a > 0, o[:, :, :3] / np.maximum(a, 1e-6), 0)
    return o


def tile_insert(img, axis, at, src, total):
    """Вставляет в позицию at (по оси axis) total пикселей, повторяя полосу src=(a, b).
    Для периодических узоров (ряды лампочек) src — ровно один период: шов не виден."""
    seg = np.take(img, range(*src), axis=axis)
    reps = int(np.ceil(total / seg.shape[axis]))
    fill = np.take(np.concatenate([seg] * reps, axis=axis), range(total), axis=axis)
    head = np.take(img, range(at), axis=axis)
    tail = np.take(img, range(at, img.shape[axis]), axis=axis)
    return np.concatenate([head, fill, tail], axis=axis)


def shadow(img, pad, sigma, dy, opacity):
    """Мягкая тень по альфе картинки; картинка увеличивается на pad с каждой стороны."""
    h, w, _ = img.shape
    H, W = h + 2 * pad, w + 2 * pad
    a = np.zeros((H, W))
    a[pad + dy : pad + dy + h, pad : pad + w] = img[: H - pad - dy, :, 3]
    k = np.exp(-0.5 * (np.arange(-3 * sigma, 3 * sigma + 1) / sigma) ** 2)
    k /= k.sum()
    a = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 0, a)
    a = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 1, a) * opacity
    fa = np.zeros((H, W))
    fc = np.zeros((H, W, 3))
    fa[pad : pad + h, pad : pad + w] = img[:, :, 3]
    fc[pad : pad + h, pad : pad + w] = img[:, :, :3]
    oa = fa + a * (1 - fa)
    out = np.zeros((H, W, 4))
    out[:, :, 3] = oa
    out[:, :, :3] = np.where(oa[..., None] > 0, fc * fa[..., None] / np.maximum(oa, 1e-6)[..., None], 0)
    return out


def energy_strip(name, size):
    """Самая ровная яркая полоса из текстуры энергии (заливка обрезается справа по ходу таймера)."""
    src = np.asarray(Image.open(os.path.join(HUD, name)).convert("RGB"), np.float64) / 255
    lum = src.mean(2)
    band = max(8, src.shape[1] * size[1] // size[0])
    best = max(
        range(0, src.shape[0] - band),
        key=lambda y: (lambda prof: prof.mean() - 2 * prof.std())(lum[y : y + band].mean(0)),
    )
    strip = Image.fromarray((src[best : best + band] * 255).astype(np.uint8)).resize(size, Image.LANCZOS)
    rgba = np.concatenate([np.asarray(strip, np.float64) / 255, np.ones((size[1], size[0], 1))], 2)
    return rgba


# Все размеры — 2x от экранных (CSS = половина).
help_bg = shadow(load("helpdesk_bg.png", crop=False), pad=48, sigma=18, dy=12, opacity=0.85)
save("helpdesk_bg_shadow.png", help_bg)
save(
    "shop_bg_shadow.png",
    stretch(help_bg, (1040, 620), 0.6, xzones=[(280, 370), (765, 855)], yzones=[(285, 495), (720, 930)]),
)
# Справка с вкладками: та же рамка в полный размер (углы и камни как у
# прежней справки), растянутая до 1280x800 на экране. Растянутые по зонам
# полосы фона дают швы, поэтому внутрь кладём фон, растянутый равномерно;
# маска (координаты helpdesk_bg_shadow) обходит плашку, камни и углы.
def help_wide(size):
    xz, yz = [(280, 370), (765, 855)], [(285, 495), (720, 930)]
    frame = stretch(help_bg, size, 1.0, xzones=xz, yzones=yz)
    h, w = help_bg.shape[:2]
    # Чистый фон без орнамента растягиваем равномерно на всю область маски
    # (до зон и после них масштаб 1, поэтому её края в результате известны)
    l, t, r, b = 200, 175, 935, 1040
    inner = frame.copy()
    inner[t : size[1] - (h - b), l : size[0] - (w - r)] = stretch(
        help_bg[265:985, 262:873], (size[0] - (w - r) - l, size[1] - (h - b) - t), 1.0
    )
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle((200, 175, 935, 1040), fill=255)
    for box in [(360, 0, 775, 265), (480, 990, 650, h), (0, 0, 260, 240), (875, 0, w, 240),
                (0, 985, 260, h), (875, 985, w, h), (0, 520, 220, 700), (915, 520, w, 700)]:
        draw.rectangle(box, fill=0)
    mask = np.asarray(mask.filter(ImageFilter.GaussianBlur(14)), np.float64)[:, :, None] / 255
    m = stretch(np.concatenate([np.ones((h, w, 3)), mask], 2), size, 1.0, xzones=xz, yzones=yz)[:, :, 3:]
    return frame * (1 - m) + inner * m


save("help_wide_shadow.png", help_wide((2560, 1600)))

# Плашка таймера: зоны — участки рамки между гнездом, центральным камнем и правым концом
for src_name, zones in [
    ("timer_plaque.png", [(143, 213), (273, 393)]),
    ("timer_plaque_urgent.png", [(140, 190), (280, 355)]),
]:
    img = load(src_name)
    s = 104 / img.shape[0]
    plaque = stretch(img, (720, 104), s, xzones=zones)
    save(src_name.replace(".png", "_hud.png"), shadow(plaque, pad=12, sigma=6, dy=4, opacity=0.8))

save("progress_track_hud.png", stretch(load("progress_track.png"), (660, 24), 24 / 51, xzones=[(52, 432)]))
save("progress_fill_hud.png", energy_strip("progress_fill.jpg", (628, 14)))

chaos = stretch(
    load("chaos_round_bg.png"), (680, 480), 1.2,
    xzones=[(93, 148), (243, 298)], yzones=[(128, 193), (268, 348)],
)
save("chaos_round_bg_hud.png", shadow(chaos, pad=24, sigma=14, dy=8, opacity=0.8))

# Голосование: та же рамка хаос-раунда, вытянутая под три вопроса и подсказку
vote = stretch(
    load("chaos_round_bg.png"), (612, 692), 1.2,
    xzones=[(93, 148), (243, 298)], yzones=[(128, 193), (268, 348)],
)
save("vote_bg_hud.png", shadow(vote, pad=24, sigma=14, dy=8, opacity=0.8))

# Казино: рамку с лампочками наращиваем целыми периодами лампочек (растяжение
# сделало бы их овальными). Арка с гербом сверху и основание с монетами снизу
# расширяются по своим гладким участкам. Координаты — исходник 500x500 без обрезки.
CASINO_BULB_X, CASINO_BULB_Y = 22.5, 22.9
CASINO_COLS, CASINO_ROWS = 6, 20  # периодов на сторону по ширине / всего по высоте
casino = load("casino_bg.png", crop=False)
CASINO_INNER = (127, 153, 373, 354)  # тёмный камень внутри лампочек: x0, y0, x1, y1
inner_src = casino[CASINO_INNER[1] : CASINO_INNER[3], CASINO_INNER[0] : CASINO_INNER[2]]
py = round(CASINO_BULB_Y)
rows_a = 7  # над боковым самоцветом, остальное — под ним
casino = tile_insert(casino, 0, 290, (290, 290 + py), py * (CASINO_ROWS - rows_a))
casino = tile_insert(casino, 0, 198, (198, 198 + py), py * rows_a)
seam_top, seam_bottom = 125, 391 + py * CASINO_ROWS  # швы по золотым планкам
grow = round(CASINO_BULB_X * CASINO_COLS)
px = round(CASINO_BULB_X)
arch = casino[:seam_top]
arch = stretch(arch, (arch.shape[1] + 2 * grow, arch.shape[0]), 1,
               xzones=[(126, 143), (166, 176), (324, 334), (356, 372)])
bulbs = casino[seam_top:seam_bottom]
bulbs = tile_insert(bulbs, 1, 352, (352, 352 + px), grow)
bulbs = tile_insert(bulbs, 1, 148, (148, 148 + px), grow)
base = casino[seam_bottom:]
base = tile_insert(base, 1, 278, (268, 288), grow)
base = tile_insert(base, 1, 222, (212, 232), grow)
casino = np.concatenate([arch, bulbs, base], axis=0)
# повторённые полосы камня дают швы — внутрь кладём растянутый исходный камень
x0, y0, x1, y1 = CASINO_INNER
x1, y1 = x1 + 2 * grow, y1 + py * CASINO_ROWS
casino[y0:y1, x0:x1] = stretch(inner_src, (x1 - x0, y1 - y0), 1)
ys, xs = np.where(casino[:, :, 3] > 0.1)
casino = casino[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
print("casino inner box:", x0 - xs.min(), y0 - ys.min(), x1 - xs.min(), y1 - ys.min(),
      "size", casino.shape[1], "x", casino.shape[0])
save("casino_bg_hud.png", shadow(casino, pad=20, sigma=10, dy=6, opacity=0.8))


def crop_alpha(img):
    ys, xs = np.where(img[:, :, 3] > 0.1)
    return img[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]


def square(img, size):
    """Вписывает по центру в прозрачный квадрат size x size."""
    h, w, _ = img.shape
    k = size / max(h, w)
    small = np.asarray(
        Image.fromarray((img * 255).astype(np.uint8)).resize(
            (max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS
        ),
        np.float64,
    ) / 255
    out = np.zeros((size, size, 4))
    y, x = (size - small.shape[0]) // 2, (size - small.shape[1]) // 2
    out[y : y + small.shape[0], x : x + small.shape[1]] = small
    return out


save("casino_reels_hud.png", load("casino_reels.png"))
save("casino_stake_hud.png", load("casino_stake.png"))
# Кнопка: сверху активная, снизу выключенная
spin = load("casino_spin_on_off.png", crop=False)
half = spin.shape[0] // 2
save("casino_spin_on_hud.png", crop_alpha(spin[:half]))
save("casino_spin_off_hud.png", crop_alpha(spin[half:]))
# Символы сеткой 2x2; имена — ключи символов с сервера (osc_casino.js)
sym = load("casino_symbols.png", crop=False)
h2, w2 = sym.shape[0] // 2, sym.shape[1] // 2
for key, (y, x) in {"circle": (0, 0), "diamond": (0, 1), "star": (1, 0), "seven": (1, 1)}.items():
    save("casino_sym_%s_hud.png" % key, square(crop_alpha(sym[y * h2 : (y + 1) * h2, x * w2 : (x + 1) * w2]), 128))

# Лента для прокрутки барабана: символы столбиком, два круга подряд (CSS сдвигает
# её на один круг и повторяет), размыта по вертикали как при быстром вращении.
# Ячейка 128x170; на экране 72x96 (osc_hud.css, .CasinoReelStrip).
cells = []
for key in ["seven", "circle", "star", "diamond"]:
    cell = np.zeros((170, 128, 4))
    cell[21:149] = load("casino_sym_%s_hud.png" % key, crop=False)
    cells.append(cell)
strip = np.concatenate(cells * 2, axis=0)
k = np.exp(-0.5 * (np.arange(-18, 19) / 6.0) ** 2)
k /= k.sum()
pm = strip.copy()
pm[:, :, :3] *= pm[:, :, 3:]
pm = np.apply_along_axis(lambda v: np.convolve(np.concatenate([v[-18:], v, v[:18]]), k, "valid"), 0, pm)
pm[:, :, :3] = np.where(pm[:, :, 3:] > 0, pm[:, :, :3] / np.maximum(pm[:, :, 3:], 1e-6), 0)
save("casino_reel_strip_hud.png", pm)

# Монетка из поля ставки (центр ~(80, 245), радиус ~24 в исходнике 500x500) —
# иконка цены предметов
stake_src = load("casino_stake.png", crop=False)
cy, cx, r = 245, 80, 24.5
coin = stake_src[int(cy - 27) : int(cy + 27), int(cx - 27) : int(cx + 27)].copy()
yy, xx = np.mgrid[: coin.shape[0], : coin.shape[1]]
dist = np.hypot(yy + 0.5 - 27, xx + 0.5 - 27)
coin[:, :, 3] *= np.clip(r - dist + 0.5, 0, 1)
save("casino_coin_hud.png", square(coin, 64))

# Лента-заголовок: в исходнике две ленты (сверху красная, снизу огненная для
# джекпота). Режем по одинаковой средней линии ленты, чтобы при смене не было
# скачка; монеты и лучи над лентой подрезаны с затуханием — иначе лезут на герб.
title_src = load("casino_title.png", crop=False)
TITLE_X = (35, 465)
TITLE_ABOVE, TITLE_BELOW, TITLE_FADE = 60, 61, 30
for name, center in [("casino_title_hud.png", 155), ("casino_title_jackpot_hud.png", 377)]:
    ribbon = title_src[center - TITLE_ABOVE : center + TITLE_BELOW, TITLE_X[0] : TITLE_X[1]].copy()
    ribbon[:TITLE_FADE, :, 3] *= np.linspace(0, 1, TITLE_FADE)[:, None]
    save(name, ribbon)
icon = Image.fromarray((load("chaos_round_icon.png") * 255).astype(np.uint8)).resize((64, 64), Image.LANCZOS)
save("chaos_round_icon_hud.png", np.asarray(icon, np.float64) / 255)
