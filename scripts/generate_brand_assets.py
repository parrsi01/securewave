#!/usr/bin/env python3
import json
import math
from pathlib import Path
from typing import Iterable, List, Tuple

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BRAND_DIR = ROOT / "assets" / "brand"

ACCENT = (0x1B, 0x6B, 0x68)
ACCENT_STRONG = (0x0F, 0x4F, 0x4C)
BACKGROUND = (0xF5, 0xF7, 0xFB)


def _cubic_point(p0, p1, p2, p3, t: float) -> Tuple[float, float]:
    inv = 1.0 - t
    x = (
        (inv ** 3) * p0[0]
        + 3 * (inv ** 2) * t * p1[0]
        + 3 * inv * (t ** 2) * p2[0]
        + (t ** 3) * p3[0]
    )
    y = (
        (inv ** 3) * p0[1]
        + 3 * (inv ** 2) * t * p1[1]
        + 3 * inv * (t ** 2) * p2[1]
        + (t ** 3) * p3[1]
    )
    return x, y


def _sample_cubic(p0, p1, p2, p3, steps: int) -> List[Tuple[float, float]]:
    return [_cubic_point(p0, p1, p2, p3, t / steps) for t in range(steps + 1)]


def _shield_points() -> List[Tuple[float, float]]:
    points: List[Tuple[float, float]] = []
    points.extend(
        _sample_cubic(
            (70, 10),
            (46, 24),
            (28, 28),
            (28, 28),
            24,
        )
    )
    points.append((28, 62))
    points.extend(
        _sample_cubic(
            (28, 62),
            (28, 95.5),
            (50, 120),
            (70, 130),
            28,
        )[1:]
    )
    points.extend(
        _sample_cubic(
            (70, 130),
            (90, 120),
            (112, 95.5),
            (112, 62),
            28,
        )[1:]
    )
    points.append((112, 28))
    points.extend(
        _sample_cubic(
            (112, 28),
            (112, 28),
            (94, 24),
            (70, 10),
            24,
        )[1:]
    )
    return points


def _gradient_fill(size: int, top: Tuple[int, int, int], bottom: Tuple[int, int, int]) -> Image.Image:
    gradient = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(gradient)
    for y in range(size):
        ratio = y / (size - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * ratio) for i in range(3))
        draw.line([(0, y), (size, y)], fill=color + (255,))
    return gradient


def _scale_points(points: Iterable[Tuple[float, float]], size: int, pad: float) -> List[Tuple[float, float]]:
    scale = (size - pad * 2) / 140.0
    return [(x * scale + pad, y * scale + pad) for x, y in points]


def _render_icon(size: int) -> Image.Image:
    oversample = 2
    work_size = size * oversample
    pad = work_size * 0.12

    base = Image.new("RGBA", (work_size, work_size), BACKGROUND + (255,))
    mask = Image.new("L", (work_size, work_size), 0)

    points = _scale_points(_shield_points(), work_size, pad)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.polygon(points, fill=255)

    gradient = _gradient_fill(work_size, ACCENT, ACCENT_STRONG)
    base = Image.composite(gradient, base, mask)

    center_x = work_size / 2
    center_y = pad + ((66 / 140) * (work_size - 2 * pad))
    circle_radius = (28 / 140) * (work_size - 2 * pad)

    draw = ImageDraw.Draw(base)
    draw.ellipse(
        [
            (center_x - circle_radius, center_y - circle_radius),
            (center_x + circle_radius, center_y + circle_radius),
        ],
        fill=BACKGROUND,
    )

    def wave_path(points: List[Tuple[float, float]], color: Tuple[int, int, int], width: float) -> None:
        scaled = _scale_points(points, work_size, pad)
        stroke_width = max(1, int(round(width)))
        mask = Image.new("L", (work_size, work_size), 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.line(scaled, fill=255, width=stroke_width, joint="curve")
        mask = mask.filter(ImageFilter.GaussianBlur(radius=1.2))
        color_layer = Image.new("RGBA", (work_size, work_size), color + (255,))
        base.paste(color_layer, (0, 0), mask)

    wave1 = _sample_cubic((42, 72), (56, 60), (88, 60), (104, 70), 80)
    wave_path(wave1, ACCENT, (6 / 140) * (work_size - 2 * pad))

    wave2 = _sample_cubic((48, 86), (60, 78), (86, 78), (100, 84), 80)
    wave_path(wave2, ACCENT_STRONG, (6 / 140) * (work_size - 2 * pad))


    return base.resize((size, size), Image.LANCZOS)


def _save_icon(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def main() -> None:
    BRAND_DIR.mkdir(parents=True, exist_ok=True)
    base_icon = _render_icon(1024)

    _save_icon(base_icon, BRAND_DIR / "app_icon_1024.png")
    _save_icon(base_icon, ROOT / "securewave_app" / "assets" / "icon.png")

    # Web icons
    _save_icon(base_icon.resize((64, 64), Image.LANCZOS), ROOT / "securewave_app" / "web" / "favicon.png")
    _save_icon(base_icon.resize((192, 192), Image.LANCZOS), ROOT / "securewave_app" / "web" / "icons" / "Icon-192.png")
    _save_icon(base_icon.resize((512, 512), Image.LANCZOS), ROOT / "securewave_app" / "web" / "icons" / "Icon-512.png")
    _save_icon(base_icon.resize((192, 192), Image.LANCZOS), ROOT / "securewave_app" / "web" / "icons" / "Icon-maskable-192.png")
    _save_icon(base_icon.resize((512, 512), Image.LANCZOS), ROOT / "securewave_app" / "web" / "icons" / "Icon-maskable-512.png")

    # iOS AppIcon set
    appicon_dir = ROOT / "securewave_app" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((appicon_dir / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents.get("images", []):
        size_text = entry.get("size")
        scale_text = entry.get("scale")
        filename = entry.get("filename")
        if not size_text or not scale_text or not filename:
            continue
        size_value = float(size_text.split("x")[0])
        scale_value = int(scale_text.replace("x", ""))
        pixel_size = int(size_value * scale_value)
        resized = base_icon.resize((pixel_size, pixel_size), Image.LANCZOS)
        _save_icon(resized, appicon_dir / filename)

    # Android launcher icons
    android_dir = ROOT / "securewave_app" / "android" / "app" / "src" / "main" / "res"
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in android_sizes.items():
        path = android_dir / folder / "ic_launcher.png"
        _save_icon(base_icon.resize((size, size), Image.LANCZOS), path)

    # macOS icons
    mac_dir = ROOT / "securewave_app" / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in mac_sizes:
        path = mac_dir / f"app_icon_{size}.png"
        _save_icon(base_icon.resize((size, size), Image.LANCZOS), path)

    print("Brand assets regenerated.")


if __name__ == "__main__":
    main()
