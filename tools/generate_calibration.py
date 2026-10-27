#!/usr/bin/env python3
"""Generate a known, rectified full-SBS stereo fixture. Requires Pillow."""
from pathlib import Path
import argparse
import json

from PIL import Image, ImageDraw, ImageFont

SIZE = (1024, 768)
TARGETS = [
    # Positive x_left - x_right is crossed disparity, perceived nearer.
    {"name": "NEAR", "center": [256, 384], "disparity_px": 24,
     "color": [61, 224, 168]},
    {"name": "SCREEN", "center": [512, 384], "disparity_px": 0,
     "color": [245, 200, 72]},
    {"name": "FAR", "center": [768, 384], "disparity_px": -16,
     "color": [92, 167, 255]},
]


def font(size: int):
    # Pin font for deterministic output on this environment; fallback permits
    # generating functional fixtures on machines without DejaVu installed.
    try:
        return ImageFont.truetype("DejaVuSans.ttf", size)
    except OSError:
        return ImageFont.load_default(size=size)


def eye_image(eye: str) -> Image.Image:
    image = Image.new("RGB", SIZE, (16, 22, 34))
    draw = ImageDraw.Draw(image)
    for x in range(64, SIZE[0], 64):
        draw.line((x, 160, x, 640), fill=(33, 44, 60), width=1)
    for y in range(192, 641, 64):
        draw.line((64, y, 960, y), fill=(33, 44, 60), width=1)
    draw.rectangle((32, 32, 991, 735), outline=(120, 137, 161), width=3)
    draw.text((512, 80), "QUEST PHOTO · STEREO TEST", font=font(32),
              fill=(235, 241, 250), anchor="mm")
    # Eye-specific identifier is intentionally not a fusible stereo target.
    eye_color = (255, 105, 125) if eye == "LEFT" else (118, 207, 255)
    draw.text((512, 128), f"{eye} EYE", font=font(24),
              fill=eye_color, anchor="mm")
    for target in TARGETS:
        sign = 1 if eye == "LEFT" else -1
        x = target["center"][0] + sign * target["disparity_px"] // 2
        y = target["center"][1]
        color = tuple(target["color"])
        draw.ellipse((x-65, y-65, x+65, y+65), fill=color)
        draw.line((x-25, y, x+25, y), fill=(16, 22, 34), width=3)
        draw.line((x, y-25, x, y+25), fill=(16, 22, 34), width=3)
        draw.text((x, y+108), target["name"], font=font(25),
                  fill=(235, 241, 250), anchor="mm")
    draw.text((512, 594), "Green in front · Yellow on screen · Blue behind", 
              font=font(25), fill=(200, 211, 228), anchor="mm")
    draw.text((512, 674), "Close one eye: only its matching eye label should appear",
              font=font(22), fill=(200, 211, 228), anchor="mm")
    return image


def generate(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    left, right = eye_image("LEFT"), eye_image("RIGHT")
    left.save(output / "stereo_left.png")
    right.save(output / "stereo_right.png")
    sbs = Image.new("RGB", (SIZE[0] * 2, SIZE[1]))
    sbs.paste(left, (0, 0))
    sbs.paste(right, (SIZE[0], 0))
    sbs.save(output / "stereo_test_sbs.png")
    metadata = {
        "format": "full-SBS", "eye_size": SIZE, "order": ["LEFT", "RIGHT"],
        "disparity_convention": "x_left - x_right; positive = nearer than screen",
        "targets": TARGETS,
        "license": "CC0-1.0 (original project calibration artwork)",
    }
    (output / "stereo_test.json").write_text(json.dumps(metadata, indent=2)+"\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[1] / "assets")
    generate(parser.parse_args().output)
