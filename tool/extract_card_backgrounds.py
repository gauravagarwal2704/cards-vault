#!/usr/bin/env python3
"""Extract the card-sized regions from the supplied Figma SVG export.

The export is a single 4369x3190 SVG with every background positioned on one
canvas. This script keeps each card's original vector nodes and follows SVG
references into <defs>, producing standalone 350x220 SVG assets without
redrawing or rasterizing the artwork.
"""

from __future__ import annotations

import argparse
import copy
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)

REFERENCE_PATTERN = re.compile(r"url\(#([^)]+)\)|^#(.+)$")
TRANSLATE_PATTERN = re.compile(
    r"translate\(\s*(-?[\d.]+)(?:[ ,]+)(-?[\d.]+)\s*\)"
)
PATH_START_PATTERN = re.compile(r"^M(-?[\d.]+)[ ,](-?[\d.]+)")


@dataclass(frozen=True)
class CardSpec:
    category: str
    index: int
    x: float
    y: float

    @property
    def file_name(self) -> str:
        return f"{self.index:02d}.svg"


def _grid(category: str, xs: list[int], ys: list[int]) -> list[CardSpec]:
    specs: list[CardSpec] = []
    for y in ys:
        for x in xs:
            specs.append(CardSpec(category, len(specs) + 1, x, y))
    return specs


def _positions(
    category: str,
    positions: list[tuple[int, int]],
) -> list[CardSpec]:
    return [
        CardSpec(category, index, x, y)
        for index, (x, y) in enumerate(positions, start=1)
    ]


CARD_SPECS = [
    *_grid("gradient", [1, 396, 791, 1186], [0, 270, 540]),
    *_grid("dual_tone", [1755, 2150, 2545, 2940], [0, 270, 540]),
    *_positions(
        "designer",
        [
            *((x, y) for y in [1080, 1350] for x in [1, 396, 791, 1186]),
            *(
                (x, y)
                for y in [1890, 2160, 2430]
                for x in [1, 396, 791, 1186, 1581, 1976]
            ),
        ],
    ),
    *_grid("gradient_blur", [1755, 2150, 2545, 2940], [1080, 1350]),
    *_grid("glassmorphism", [3558], [1080, 1350]),
    *_grid("monochrome", [4019], [1080, 1350]),
    *_grid("image", [0, 395, 790, 1185, 1580, 1975], [2970]),
]


def _local_name(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _float(value: str | None, default: float = 0) -> float:
    try:
        return float(value) if value is not None else default
    except ValueError:
        return default


def _origin_from_rect(element: ET.Element) -> tuple[float, float] | None:
    if _local_name(element) not in {"rect", "mask", "foreignObject"}:
        return None
    width = _float(element.get("width"))
    height = _float(element.get("height"))
    x = _float(element.get("x"))
    y = _float(element.get("y"))
    if width == 350 and height == 220:
        return x, y
    # Figma's glass backdrop foreignObjects include the shadow/blur overflow.
    if width == 396 and height == 267 and x == 3535:
        return 3558, y + 20
    return None


def _clip_origin(element: ET.Element) -> tuple[float, float] | None:
    for child in element.iter():
        match = TRANSLATE_PATTERN.search(child.get("transform", ""))
        if match:
            return float(match.group(1)), float(match.group(2))
        origin = _origin_from_rect(child)
        if origin is not None:
            return origin
    return None


def _collect_references(element: ET.Element) -> set[str]:
    references: set[str] = set()
    for child in element.iter():
        for value in child.attrib.values():
            for match in REFERENCE_PATTERN.finditer(value):
                reference = match.group(1) or match.group(2)
                if reference:
                    references.add(reference)
    return references


def _same_origin(
    left: tuple[float, float] | None,
    right: tuple[float, float],
) -> bool:
    return left is not None and abs(left[0] - right[0]) < 0.01 and abs(
        left[1] - right[1]
    ) < 0.01


def _classify_node(
    element: ET.Element,
    definitions: dict[str, ET.Element],
) -> tuple[float, float] | None:
    # A clipped/masked group often contains local 0,0 geometry. Its referenced
    # viewport is the authoritative position on the exported canvas.
    for attribute in ("clip-path", "mask"):
        value = element.get(attribute)
        if value is None:
            continue
        match = REFERENCE_PATTERN.search(value)
        reference = (match.group(1) or match.group(2)) if match else None
        definition = definitions.get(reference) if reference else None
        if definition is not None:
            origin = _clip_origin(definition)
            if origin is not None:
                return origin

    for child in element.iter():
        origin = _origin_from_rect(child)
        if origin is not None:
            return origin

    for reference in _collect_references(element):
        definition = definitions.get(reference)
        if definition is None:
            continue
        origin = _clip_origin(definition)
        if origin is not None:
            return origin

    if _local_name(element) == "path":
        match = PATH_START_PATTERN.match(element.get("d", ""))
        if match:
            x = float(match.group(1))
            y = float(match.group(2))
            # Dual-tone overlays begin 121px below each card's top edge.
            return x, y - 121
    return None


def _definition_closure(
    selected: list[ET.Element],
    definitions: dict[str, ET.Element],
) -> list[ET.Element]:
    pending: list[str] = []
    for element in selected:
        pending.extend(_collect_references(element))

    seen: set[str] = set()
    ordered: list[ET.Element] = []
    while pending:
        reference = pending.pop()
        if reference in seen:
            continue
        seen.add(reference)
        definition = definitions.get(reference)
        if definition is None:
            continue
        ordered.append(definition)
        pending.extend(_collect_references(definition))
    return ordered


def extract(source: Path, output: Path) -> None:
    tree = ET.parse(source)
    source_root = tree.getroot()
    source_defs = source_root.find(f"{{{SVG_NS}}}defs")
    if source_defs is None:
        raise ValueError("Source SVG has no <defs> section")

    # Figma sometimes emits masks beside the drawable nodes instead of inside
    # <defs>. Index every id in the document so groups using those masks retain
    # their decorative layers in the standalone card.
    definitions = {
        element_id: element
        for element in source_root.iter()
        if (element_id := element.get("id")) is not None
    }
    drawable_nodes = [
        element
        for element in source_root
        if _local_name(element) not in {"defs", "mask", "clipPath"}
    ]
    classified = [
        (element, _classify_node(element, definitions))
        for element in drawable_nodes
    ]

    output.mkdir(parents=True, exist_ok=True)
    for spec in CARD_SPECS:
        origin = (spec.x, spec.y)
        selected = [
            element
            for element, element_origin in classified
            if _same_origin(element_origin, origin)
        ]
        if not selected:
            raise ValueError(
                f"No SVG nodes found for {spec.category}/{spec.index:02d} "
                f"at {origin}"
            )

        root = ET.Element(
            f"{{{SVG_NS}}}svg",
            {
                "width": "350",
                "height": "220",
                "viewBox": f"{spec.x:g} {spec.y:g} 350 220",
                "fill": "none",
            },
        )
        title = ET.SubElement(root, f"{{{SVG_NS}}}title")
        title.text = f"{spec.category.replace('_', ' ').title()} {spec.index:02d}"

        defs = ET.SubElement(root, f"{{{SVG_NS}}}defs")
        for definition in _definition_closure(selected, definitions):
            defs.append(copy.deepcopy(definition))
        for element in selected:
            root.append(copy.deepcopy(element))

        category_dir = output / spec.category
        category_dir.mkdir(parents=True, exist_ok=True)
        ET.ElementTree(root).write(
            category_dir / spec.file_name,
            encoding="utf-8",
            xml_declaration=True,
        )

    count = sum(1 for _ in output.glob("*/*.svg"))
    print(f"Extracted {count} card backgrounds into {output}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    extract(args.source, args.output)


if __name__ == "__main__":
    main()
