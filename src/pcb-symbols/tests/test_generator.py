from __future__ import annotations

import importlib.util
import re
import struct
import sys
from pathlib import Path

from PIL import Image


PLUGIN_DIR = Path(__file__).resolve().parents[1]
SCRIPT_PATH = PLUGIN_DIR / "tools" / "generate_glyph_data.py"
FONT_PATH = PLUGIN_DIR.parents[1] / "assets" / "source-font" / "Mooretronics.ttf"
ICON_DIR = PLUGIN_DIR / "icons"


def _load_generator():
    spec = importlib.util.spec_from_file_location("mts_generator", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_font_contains_all_supported_symbols() -> None:
    generator = _load_generator()
    digest, units_per_em = generator._font_identity(FONT_PATH)
    assert len(digest) == 64
    assert units_per_em == 4096
    assert len(generator.SYMBOLS) == 26


def test_generated_skill_data_is_complete() -> None:
    text = (PLUGIN_DIR / "mooretronics_glyphs.il").read_text(encoding="ascii")
    characters = re.findall(r'^\s{8}"([A-Za-z])"$', text, flags=re.MULTILINE)
    assert characters == [
        "A", "a", "B", "b", "C", "c", "E", "e", "F", "G", "g",
        "H", "N", "O", "o", "P", "p", "R", "r", "S", "T", "U",
        "W", "w", "X", "x",
    ]
    assert '_mts_glyph_format = "OUTLINE_V1"' in text
    contour_count = len(re.findall(r"^ {12}list\($", text, flags=re.MULTILINE))
    assert 300 <= contour_count <= 450
    assert text.count(":") > 10000


def test_outline_hierarchy_is_valid() -> None:
    generator = _load_generator()
    font = generator.TTFont(str(FONT_PATH))
    for char, _ in generator.SYMBOLS:
        contours = generator._outline_glyph(font, char, 2.5)
        assert contours
        for parent, depth, points in contours:
            assert len(points) >= 3
            if parent < 0:
                assert depth == 0
            else:
                assert parent < len(contours)
                assert contours[parent][1] == depth - 1


def test_button_icons_are_complete_and_16_6_compatible() -> None:
    icons = sorted(ICON_DIR.glob("mts_symbol_*.bmp"))
    assert len(icons) == 26
    assert [path.name for path in icons] == [
        f"mts_symbol_{index:02d}.bmp" for index in range(26)
    ]
    for path in icons:
        header = path.read_bytes()[:64]
        assert struct.unpack_from("<H", header, 28)[0] == 8
        palette_offset = 14 + struct.unpack_from("<I", header, 14)[0]
        assert path.read_bytes()[palette_offset:palette_offset + 8] == bytes(
            (255, 255, 255, 0, 254, 254, 254, 0)
        )
        with Image.open(path) as image:
            assert image.format == "BMP"
            assert image.size == (72, 36)
            assert image.mode == "P"
            assert image.getpixel((0, 0)) == 0
            assert image.getpalette()[:6] == [255, 255, 255, 254, 254, 254]
            assert len(image.getcolors(maxcolors=256)) > 2


def test_inverse_nested_voids_can_be_strictly_inset() -> None:
    generator = _load_generator()
    font = generator.TTFont(str(FONT_PATH))
    skipped_microscopic = 0
    for char, _ in generator.SYMBOLS:
        contours = generator._outline_glyph(font, char, 2.5)
        for parent, depth, points in contours:
            if parent < 0 or depth % 2 != 0:
                continue
            if abs(generator._signed_area(points)) < 0.00002:
                skipped_microscopic += 1
                continue
            center_x = sum(x for x, _ in points) / len(points)
            center_y = sum(y for _, y in points) / len(points)
            inset = [
                (
                    center_x + (x - center_x) * 0.998,
                    center_y + (y - center_y) * 0.998,
                )
                for x, y in points
            ]
            parent_points = contours[parent][2]
            assert all(
                generator._point_in_polygon(point, parent_points)
                for point in inset
            ), (char, parent, depth)
    assert skipped_microscopic >= 1


def main() -> int:
    test_font_contains_all_supported_symbols()
    test_generated_skill_data_is_complete()
    test_outline_hierarchy_is_valid()
    test_button_icons_are_complete_and_16_6_compatible()
    test_inverse_nested_voids_can_be_strictly_inset()
    print("MTS_GENERATOR_TESTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
