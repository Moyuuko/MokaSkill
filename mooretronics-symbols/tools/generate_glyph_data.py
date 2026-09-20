#!/usr/bin/env python3
"""Generate smooth Allegro outline geometry from Mooretronics.ttf.

TrueType quadratic Bezier outlines are flattened adaptively into closed
polygons. The generated SKILL data preserves contour nesting so Allegro can
create one filled shape per solid island and true voids for counters/holes.
"""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont, ImageOps
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont


SYMBOLS = (
    ("A", "Attention + text"), ("a", "Attention (IEC 348)"),
    ("B", "Recycling in circle"), ("b", "Recycling"),
    ("C", "CE"), ("c", "CSA"), ("E", "ESD + text"), ("e", "ESD"),
    ("F", "FCC"), ("G", "Earth ground (IEC 5017)"),
    ("g", "Frame ground"), ("H", "High voltage (IEC 60417)"),
    ("N", "Noiseless earth (IEC 5018)"), ("O", "Open Hardware + text"),
    ("o", "Open Hardware"), ("P", "Pb Free + text"), ("p", "Pb Free"),
    ("R", "RoHS + tick"), ("r", "RCM mark"),
    ("S", "Protective earth (IEC 5019)"), ("T", "C-Tick"),
    ("U", "UL"), ("W", "WEEE / recycling"), ("w", "Attention (filled)"),
    ("X", "Hot surface + text"), ("x", "Hot surface"),
)

Point = tuple[float, float]
Contour = list[Point]


def _midpoint(point1: Point, point2: Point) -> Point:
    return ((point1[0] + point2[0]) / 2.0, (point1[1] + point2[1]) / 2.0)


def _signed_area(points: Contour) -> float:
    return sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    ) / 2.0


class FlattenPen(BasePen):
    """Collect line-only contours with adaptive Bezier subdivision."""

    def __init__(self, glyph_set, tolerance: float):
        super().__init__(glyph_set)
        self.tolerance = tolerance
        self.contours: list[Contour] = []
        self._contour: Contour = []

    def _moveTo(self, point: Point) -> None:  # noqa: N802
        self._finish_contour()
        self._contour = [tuple(map(float, point))]

    def _lineTo(self, point: Point) -> None:  # noqa: N802
        point = tuple(map(float, point))
        if not self._contour or point != self._contour[-1]:
            self._contour.append(point)

    @staticmethod
    def _distance_to_line(point: Point, start: Point, end: Point) -> float:
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = math.hypot(dx, dy)
        if length == 0.0:
            return math.hypot(point[0] - start[0], point[1] - start[1])
        numerator = abs(
            dy * point[0] - dx * point[1]
            + end[0] * start[1] - end[1] * start[0]
        )
        return numerator / length

    def _flatten_quadratic(
        self, start: Point, control: Point, end: Point, depth: int = 0
    ) -> None:
        if depth >= 16 or self._distance_to_line(control, start, end) <= self.tolerance:
            self._lineTo(end)
            return
        point01 = _midpoint(start, control)
        point12 = _midpoint(control, end)
        middle = _midpoint(point01, point12)
        self._flatten_quadratic(start, point01, middle, depth + 1)
        self._flatten_quadratic(middle, point12, end, depth + 1)

    def _qCurveToOne(self, control: Point, end: Point) -> None:  # noqa: N802
        self._flatten_quadratic(self._contour[-1], control, end)

    def _flatten_cubic(
        self, start: Point, control1: Point, control2: Point, end: Point,
        depth: int = 0,
    ) -> None:
        flatness = max(
            self._distance_to_line(control1, start, end),
            self._distance_to_line(control2, start, end),
        )
        if depth >= 16 or flatness <= self.tolerance:
            self._lineTo(end)
            return
        point01 = _midpoint(start, control1)
        point12 = _midpoint(control1, control2)
        point23 = _midpoint(control2, end)
        point012 = _midpoint(point01, point12)
        point123 = _midpoint(point12, point23)
        middle = _midpoint(point012, point123)
        self._flatten_cubic(start, point01, point012, middle, depth + 1)
        self._flatten_cubic(middle, point123, point23, end, depth + 1)

    def _curveToOne(  # noqa: N802
        self, control1: Point, control2: Point, end: Point
    ) -> None:
        self._flatten_cubic(self._contour[-1], control1, control2, end)

    def _closePath(self) -> None:  # noqa: N802
        self._finish_contour()

    def _endPath(self) -> None:  # noqa: N802
        self._finish_contour()

    def _finish_contour(self) -> None:
        if len(self._contour) >= 3:
            if self._contour[-1] == self._contour[0]:
                self._contour.pop()
            if len(self._contour) >= 3 and abs(_signed_area(self._contour)) > 0.01:
                self.contours.append(self._contour)
        self._contour = []


def _point_in_polygon(point: Point, polygon: Contour) -> bool:
    x, y = point
    inside = False
    previous = polygon[-1]
    for current in polygon:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y):
            crossing_x = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < crossing_x:
                inside = not inside
        previous = current
    return inside


def _font_identity(font_path: Path) -> tuple[str, int]:
    font = TTFont(str(font_path), lazy=True)
    family = font["name"].getDebugName(1) or ""
    cmap = font.getBestCmap()
    missing = [char for char, _ in SYMBOLS if ord(char) not in cmap]
    if missing:
        raise ValueError(f"Font is missing required characters: {missing}")
    if family.lower() != "mooretronics":
        raise ValueError(f"Expected Mooretronics font, found {family!r}")
    digest = hashlib.sha256(font_path.read_bytes()).hexdigest()
    return digest, int(font["head"].unitsPerEm)


def _remove_redundant_points(points: Contour) -> Contour:
    cleaned: Contour = []
    for point in points:
        if not cleaned or point != cleaned[-1]:
            cleaned.append(point)
    changed = True
    while changed and len(cleaned) >= 4:
        changed = False
        result: Contour = []
        count = len(cleaned)
        for index, point in enumerate(cleaned):
            previous = cleaned[(index - 1) % count]
            following = cleaned[(index + 1) % count]
            cross = (
                (point[0] - previous[0]) * (following[1] - point[1])
                - (point[1] - previous[1]) * (following[0] - point[0])
            )
            if abs(cross) <= 1e-10:
                changed = True
            else:
                result.append(point)
        cleaned = result
    return cleaned


def _normalize_contours(contours: list[Contour]) -> list[Contour]:
    all_points = [point for contour in contours for point in contour]
    if not all_points:
        raise ValueError("Glyph has no outline points")
    min_x = min(point[0] for point in all_points)
    max_x = max(point[0] for point in all_points)
    min_y = min(point[1] for point in all_points)
    max_y = max(point[1] for point in all_points)
    height = max_y - min_y
    if height <= 0.0:
        raise ValueError("Glyph outline has zero height")
    center_x = (min_x + max_x) / 2.0
    center_y = (min_y + max_y) / 2.0
    normalized = []
    for contour in contours:
        points = [
            ((x - center_x) / height, (y - center_y) / height)
            for x, y in contour
        ]
        points = _remove_redundant_points(points)
        if len(points) >= 3:
            normalized.append(points)
    return normalized


def _contour_hierarchy(contours: list[Contour]) -> list[tuple[int, int, Contour]]:
    areas = [abs(_signed_area(contour)) for contour in contours]
    parents: list[int] = []
    for index, contour in enumerate(contours):
        containing = [
            candidate for candidate, other in enumerate(contours)
            if candidate != index and areas[candidate] > areas[index]
            and _point_in_polygon(contour[0], other)
        ]
        parent = min(containing, key=lambda item: areas[item]) if containing else -1
        parents.append(parent)

    depths: list[int] = []
    for index in range(len(contours)):
        depth = 0
        parent = parents[index]
        seen = {index}
        while parent >= 0:
            if parent in seen:
                raise ValueError("Cyclic contour hierarchy")
            seen.add(parent)
            depth += 1
            parent = parents[parent]
        depths.append(depth)
    return [(parents[index], depths[index], contour) for index, contour in enumerate(contours)]


def _outline_glyph(
    font: TTFont, char: str, tolerance: float
) -> list[tuple[int, int, Contour]]:
    glyph_set = font.getGlyphSet()
    glyph_name = font.getBestCmap()[ord(char)]
    pen = FlattenPen(glyph_set, tolerance)
    glyph_set[glyph_name].draw(pen)
    pen._finish_contour()
    return _contour_hierarchy(_normalize_contours(pen.contours))


def _skill_number(value: float) -> str:
    if abs(value) < 0.00000005:
        value = 0.0
    return f"{value:.7f}"


def _format_points(points: Iterable[Point]) -> list[str]:
    return [f"{_skill_number(x)}:{_skill_number(y)}" for x, y in points]


def write_skill_data(
    output_path: Path, font_path: Path, curve_tolerance: float
) -> dict[str, tuple[int, int]]:
    digest, units_per_em = _font_identity(font_path)
    font = TTFont(str(font_path))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    counts: dict[str, tuple[int, int]] = {}
    lines = [
        "; Auto-generated by tools/generate_glyph_data.py. Do not edit by hand.",
        f"; Source font SHA-256: {digest}",
        f"; Source units per em: {units_per_em}",
        f"; Adaptive curve tolerance: {curve_tolerance:.3f} font units",
        "", 'defvar(_mts_font_sha256 "")', 'defvar(_mts_glyph_format "")',
        "defvar(_mts_curve_tolerance_units 0.0)",
        "defvar(_mts_glyph_data nil)", f'_mts_font_sha256 = "{digest}"',
        '_mts_glyph_format = "OUTLINE_V1"',
        f"_mts_curve_tolerance_units = {curve_tolerance:.3f}",
        "_mts_glyph_data = list(",
    ]

    for char, label in SYMBOLS:
        contours = _outline_glyph(font, char, curve_tolerance)
        if not contours:
            raise ValueError(f"Character {char!r} produced no contours")
        point_count = sum(len(points) for _, _, points in contours)
        counts[char] = (len(contours), point_count)
        lines.extend(["    list(", f'        "{char}"', f'        "{label}"', "        list("])
        for parent, depth, points in contours:
            lines.extend([
                "            list(", f"                {parent}",
                f"                {depth}", "                list(",
            ])
            point_strings = _format_points(points)
            for start in range(0, len(point_strings), 6):
                lines.append("                    " + " ".join(point_strings[start:start + 6]))
            lines.extend(["                )", "            )"])
        lines.extend(["        )", "    )"])
    lines.extend([")", ""])
    output_path.write_text("\n".join(lines), encoding="ascii", newline="\n")
    return counts


def write_preview(output_path: Path, font_path: Path) -> None:
    font = ImageFont.truetype(str(font_path), size=92)
    label_font = ImageFont.truetype("arial.ttf", size=18)
    cell_width, cell_height, columns = 360, 138, 3
    rows = (len(SYMBOLS) + columns - 1) // columns
    image = Image.new("RGB", (cell_width * columns, cell_height * rows), "white")
    draw = ImageDraw.Draw(image)
    for index, (char, label) in enumerate(SYMBOLS):
        col, row = index % columns, index // columns
        x, y = col * cell_width, row * cell_height
        draw.rectangle((x, y, x + cell_width - 1, y + cell_height - 1), outline="#d8d8d8")
        draw.text((x + 16, y + 9), char, font=font, fill="black")
        draw.text((x + 160, y + 43), label, font=label_font, fill="#222222")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)


def write_icon_buttons(output_dir: Path, font_path: Path) -> None:
    """Write 8-bit BMP assets suitable for Allegro 16.6 bitmap buttons."""
    output_dir.mkdir(parents=True, exist_ok=True)
    expected_names = {
        f"mts_symbol_{index:02d}.bmp" for index in range(len(SYMBOLS))
    }
    for existing in output_dir.glob("mts_symbol_*.bmp"):
        if existing.name not in expected_names:
            existing.unlink()
    font = ImageFont.truetype(str(font_path), size=320)
    icon_width, icon_height = 72, 36
    content_width, content_height = 66, 32

    for index, (char, _) in enumerate(SYMBOLS):
        bbox = font.getbbox(char)
        glyph_width = max(1, bbox[2] - bbox[0])
        glyph_height = max(1, bbox[3] - bbox[1])
        source = Image.new("L", (glyph_width + 16, glyph_height + 16), 255)
        draw = ImageDraw.Draw(source)
        draw.text((8 - bbox[0], 8 - bbox[1]), char, font=font, fill=0)
        ink_bbox = ImageOps.invert(source).getbbox()
        if ink_bbox is None:
            raise ValueError(f"Character {char!r} produced an empty icon")
        glyph = source.crop(ink_bbox)
        glyph.thumbnail((content_width, content_height), Image.Resampling.LANCZOS)

        icon = Image.new("L", (icon_width, icon_height), 255)
        x = (icon_width - glyph.width) // 2
        y = (icon_height - glyph.height) // 2
        icon.paste(glyph, (x, y))

        # Keep the antialiased gray edge pixels. Allegro 16.6 accepts indexed
        # bitmaps with up to 256 colors; white must remain palette index 0 so
        # the button background blends correctly.
        indexed = ImageOps.invert(icon).convert("P")
        palette: list[int] = []
        for palette_index in range(256):
            shade = 255 - palette_index
            palette.extend((shade, shade, shade))
        indexed.putpalette(palette)
        indexed.save(output_dir / f"mts_symbol_{index:02d}.bmp", format="BMP")


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    plugin_dir = script_dir.parent
    default_font = plugin_dir.parent / "资源" / "Mooretronics.ttf"
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", type=Path, default=default_font)
    parser.add_argument("--output", type=Path, default=plugin_dir / "mooretronics_glyphs.il")
    parser.add_argument("--preview", type=Path, default=plugin_dir / "symbols_preview.png")
    parser.add_argument("--icons", type=Path, default=plugin_dir / "icons")
    parser.add_argument(
        "--curve-tolerance", type=float, default=2.5,
        help="Maximum Bezier-to-line deviation in font units (lower is smoother)",
    )
    args = parser.parse_args()
    if args.curve_tolerance <= 0.0 or args.curve_tolerance > 100.0:
        parser.error("--curve-tolerance must be greater than 0 and at most 100")
    counts = write_skill_data(args.output, args.font, args.curve_tolerance)
    write_preview(args.preview, args.font)
    write_icon_buttons(args.icons, args.font)
    print(f"Generated {args.output} from {args.font}")
    print(
        f"Glyphs: {len(counts)}; contours: {sum(v[0] for v in counts.values())}; "
        f"points: {sum(v[1] for v in counts.values())}"
    )
    print(f"Preview: {args.preview}")
    print(f"Button icons: {args.icons}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
