"""Собирает HUD-подложки из исходных картинок в content/panorama/images/custom_game/hud.

Исходники (рисованные) не меняются; скрипт пишет *_hud.png / *_shadow.png:
растягивает рамки только по гладким участкам (углы и камни не искажаются),
запекает тень по контуру (box-shadow в Panorama только прямоугольный).
Зоны растяжения подобраны вручную под текущие картинки — после замены
исходника их нужно подобрать заново. Запуск: python tools/hud_assets.py
"""
import os

import numpy as np
from PIL import Image

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
icon = Image.fromarray((load("chaos_round_icon.png") * 255).astype(np.uint8)).resize((64, 64), Image.LANCZOS)
save("chaos_round_icon_hud.png", np.asarray(icon, np.float64) / 255)
