#!/usr/bin/env python3
"""Build the six Gradient 2.0 previews affected by SVG filter seams.

macOS Quick Look and Flutter's SVG stack rasterize several of Figma's blurred
filter regions as hard rectangles. The checked-in Figma reference montage is
therefore the authoritative raster source for these six cards.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
REFERENCE = (
    REPOSITORY_ROOT
    / "design_sources/card_backgrounds/gradient_blur/reference-gradient-2.0.png"
)
OUTPUT = REPOSITORY_ROOT / "assets/card_backgrounds/gradient_blur"

# Card bounds measured from the original 2020x868 Figma reference screenshot.
CARD_WIDTH = 417
CARD_HEIGHT = 262
CARD_X = [65, 535, 1005, 1475]
CARD_Y = [153, 474]
TARGET_SIZE = (700, 440)
SEAM_AFFECTED = {2, 3, 4, 6, 7, 8}


def main() -> None:
    image = Image.open(REFERENCE).convert("RGB")
    if image.size != (2020, 868):
        raise ValueError(f"Unexpected reference size: {image.size}")

    card_number = 1
    for top in CARD_Y:
        for left in CARD_X:
            if card_number in SEAM_AFFECTED:
                crop = image.crop(
                    (left, top, left + CARD_WIDTH, top + CARD_HEIGHT)
                )
                preview = crop.resize(TARGET_SIZE, Image.Resampling.LANCZOS)
                preview.save(
                    OUTPUT / f"{card_number:02}.png",
                    "PNG",
                    optimize=True,
                )
            card_number += 1

    print(f"Rebuilt {len(SEAM_AFFECTED)} Gradient 2.0 previews")


if __name__ == "__main__":
    main()
