"""Build the Sorter Crate placeholder art and the files the game actually loads.

Run from the repo root:

    python3 tools/build_tiles.py --placeholders

That redraws the temporary crate, writes the 2x and 1x sheets, and packs
them. The real art replaces the same files later. See docs/art/SPRITE-SPEC.md.

    python3 tools/build_tiles.py
        Pack whatever is already in the 2x sheet. Use this after dropping in
        the designer's sheet (same size, same cell order).

    python3 tools/build_tiles.py --from-faces
        Rebuild the sheet from the four face PNGs, then pack it.
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pztile import PackEntry, PackPage, TileDef, Tileset, encode_pack, encode_tiles, write_tiles_text

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "Contents" / "mods" / "PZSorter"
TEX_2X = MOD / "common" / "media" / "textures" / "pzsorter" / "2x"
TEX_1X = MOD / "common" / "media" / "textures" / "pzsorter" / "1x"
TILES_PATH = MOD / "common" / "media" / "pzsorter_crate.tiles"
TILES_TEXT_PATH = MOD / "common" / "media" / "pzsorter_crate.tiles.txt"
PACK_PATH = MOD / "common" / "media" / "texturepacks" / "pzsorter_crate.pack"
POSTER_PATH = MOD / "42" / "poster.png"
ICON_PATH = MOD / "42" / "icon.png"

# The tilesheet the game and TileZed both expect: 8 cells across, 8 down.
# Only the first four cells are painted. The rest stay empty on purpose so a
# later sheet can drop into the same grid.
SHEET_COLUMNS = 8
SHEET_ROWS = 8
CELL_W = 128
CELL_H = 256
SHEET_W = SHEET_COLUMNS * CELL_W
SHEET_H = SHEET_ROWS * CELL_H

# Sprite names are "<tileset>_<index>". Index 0 is the top-left cell.
TILESET_NAME = "pzsorter_crate_01"
# Inside the .tiles file this must be 1..512. It is NOT the mod.info number.
TILESET_INDEX = 1

# Order is the build-menu rotation order we tell the entity script to use.
# East, then South, then West, then North. See SPRITE-SPEC for the sources
# and the part that is still an assumption.
FACING_ORDER = ("E", "S", "W", "N")

CAPACITY = "50"
PAGE_SIZE = 1024
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def sprite_name(index: int) -> str:
    return "%s_%s" % (TILESET_NAME, index)


def face_path(root: Path, index: int) -> Path:
    return root / "faces" / ("%s.png" % sprite_name(index))


def sheet_path(root: Path) -> Path:
    return root / ("%s.png" % TILESET_NAME)


def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:
        return ImageFont.load_default()


def _lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def _diamond(cx, cy, hw, hh):
    return {
        "n": (cx, cy - hh),
        "e": (cx + hw, cy),
        "s": (cx, cy + hh),
        "w": (cx - hw, cy),
    }


def _quad(draw, points, fill, outline=None):
    draw.polygon(points, fill=fill, outline=outline)


def _plank_lines(draw, top_left, top_right, bot_right, bot_left, color, count):
    for i in range(1, count):
        t = i / float(count)
        draw.line(
            [_lerp(top_left, bot_left, t), _lerp(top_right, bot_right, t)],
            fill=color,
            width=1,
        )


def _band(draw, top_left, top_right, bot_right, bot_left, t0, t1, color):
    _quad(
        draw,
        [
            _lerp(top_left, bot_left, t0),
            _lerp(top_right, bot_right, t0),
            _lerp(top_right, bot_right, t1),
            _lerp(top_left, bot_left, t1),
        ],
        color,
    )


def _arrow(draw, origin, scale, color):
    """A small branching arrow, drawn in screen pixels around origin."""

    ox, oy = origin
    s = scale
    stem_top = (ox, oy - 10 * s)
    stem_bot = (ox, oy + 8 * s)
    draw.line([stem_top, stem_bot], fill=color, width=max(2, int(2 * s)))
    draw.polygon(
        [(ox, oy - 16 * s), (ox - 6 * s, oy - 6 * s), (ox + 6 * s, oy - 6 * s)],
        fill=color,
    )
    draw.line([(ox, oy + 2 * s), (ox - 12 * s, oy + 12 * s)], fill=color, width=max(2, int(2 * s)))
    draw.line([(ox, oy + 2 * s), (ox + 12 * s, oy + 12 * s)], fill=color, width=max(2, int(2 * s)))
    draw.polygon(
        [
            (ox - 12 * s, oy + 12 * s),
            (ox - 18 * s, oy + 8 * s),
            (ox - 14 * s, oy + 18 * s),
        ],
        fill=color,
    )
    draw.polygon(
        [
            (ox + 12 * s, oy + 12 * s),
            (ox + 18 * s, oy + 8 * s),
            (ox + 14 * s, oy + 18 * s),
        ],
        fill=color,
    )


def _text_center(draw, xy, text, font, fill):
    box = draw.textbbox((0, 0), text, font=font)
    w = box[2] - box[0]
    h = box[3] - box[1]
    draw.text((xy[0] - w / 2, xy[1] - h / 2), text, font=font, fill=fill)


def draw_placeholder_face(facing: str) -> Image.Image:
    """One 128x256 cell. The crate sits on the floor diamond at the bottom.

    The diamond's corners, in this cell, are the usual 2x floor marker:
    north (64, 192), east (128, 224), south (64, 256), west (0, 224).
    The crate is inset so it does not spill onto the next tile.
    """

    image = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # Soft contact shadow. Alpha stays low. We pack the full cell, so this
    # shadow is not used as a trim box.
    draw.ellipse((18, 214, 110, 250), fill=(0, 0, 0, 45))

    base = _diamond(64, 226, 46, 20)
    top = _diamond(64, 226 - 50, 46, 20)

    wood_left = (122, 96, 62, 255)
    wood_right = (96, 74, 46, 255)
    seam = (62, 46, 30, 255)
    yellow = (214, 168, 42, 255)
    yellow_dark = (168, 124, 28, 255)

    # Screen-left face (the side the camera sees toward the south/west).
    left = [top["w"], top["s"], base["s"], base["w"]]
    right = [top["e"], top["s"], base["s"], base["e"]]
    lid = [top["n"], top["e"], top["s"], top["w"]]

    _quad(draw, left, wood_left, seam)
    _quad(draw, right, wood_right, seam)
    _plank_lines(draw, left[0], left[1], left[2], left[3], seam, 4)
    _plank_lines(draw, right[0], right[1], right[2], right[3], seam, 4)

    # Yellow stripe on both visible faces. The facing we are drawing gets
    # the brighter stripe, so rotation is visible even at a glance.
    left_yellow = yellow if facing in ("S", "W") else yellow_dark
    right_yellow = yellow if facing in ("E", "N") else yellow_dark
    _band(draw, left[0], left[1], left[2], left[3], 0.42, 0.64, left_yellow)
    _band(draw, right[0], right[1], right[2], right[3], 0.42, 0.64, right_yellow)

    _quad(draw, lid, (148, 116, 74, 255), seam)

    # Metal drop-slot plate, inset on the lid.
    plate = _diamond(64, top["n"][1] + 20, 28, 12)
    _quad(draw, [plate["n"], plate["e"], plate["s"], plate["w"]], (132, 136, 140, 255), (70, 74, 78, 255))
    slot = _diamond(64, plate["n"][1] + 12, 16, 4)
    _quad(draw, [slot["n"], slot["e"], slot["s"], slot["w"]], (28, 30, 32, 255))
    for corner in (plate["n"], plate["e"], plate["s"], plate["w"]):
        draw.ellipse(
            (corner[0] - 1.5, corner[1] - 1.5, corner[0] + 1.5, corner[1] + 1.5),
            fill=(50, 52, 54, 255),
        )

    # Branching arrow on the brighter face.
    if facing in ("E", "N"):
        _arrow(draw, (86, 214), 0.55, (24, 24, 24, 255))
    else:
        _arrow(draw, (42, 214), 0.55, (24, 24, 24, 255))

    # Hanging name tag. East/North hang it on the right face, South/West on
    # the left, so the four cells are not copies of each other.
    if facing in ("E", "N"):
        tag_x, tag_y = 78, 228
    else:
        tag_x, tag_y = 36, 228
    draw.line([(tag_x + 7, tag_y), (tag_x + 7, tag_y + 6)], fill=(40, 40, 40, 255), width=1)
    draw.rectangle((tag_x, tag_y + 6, tag_x + 14, tag_y + 28), fill=(196, 164, 112, 255), outline=(90, 70, 40, 255))

    # The word TEMP is the "this is not the real art" mark. It sits on the
    # crate, not in the empty space above it, so it does not float in the air.
    temp_font = _font(10)
    if facing in ("E", "N"):
        banner = (72, 198, 108, 210)
    else:
        banner = (22, 198, 58, 210)
    draw.rectangle(banner, fill=(176, 32, 32, 230))
    _text_center(
        draw,
        ((banner[0] + banner[2]) / 2, (banner[1] + banner[3]) / 2),
        "TEMP",
        temp_font,
        (255, 255, 255, 255),
    )
    # Facing letter, drawn last so the stripe and the TEMP banner cannot
    # cover it. The in-game check is that this letter matches the build
    # menu's facing. It sits on the lid, which is empty space in the cell
    # above the stripe.
    letter_font = _font(12)
    draw.rectangle((54, 162, 74, 178), fill=(20, 20, 20, 255))
    _text_center(draw, (64, 170), facing, letter_font, (255, 214, 64, 255))
    return image


def assemble_sheet(faces: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    for index, face in enumerate(faces):
        if face.size != (CELL_W, CELL_H):
            raise ValueError("face %s is %s, expected %sx%s" % (index, face.size, CELL_W, CELL_H))
        col = index % SHEET_COLUMNS
        row = index // SHEET_COLUMNS
        sheet.paste(face, (col * CELL_W, row * CELL_H))
    return sheet


def halve_nearest(image: Image.Image) -> Image.Image:
    # 1x art is exactly half of 2x, nearest-neighbour, so pixels stay crisp.
    # HydeCo's notes say a linear shrink (or a linear enlarge of 1x art) blurs.
    return image.resize((image.width // 2, image.height // 2), Image.Resampling.NEAREST)


def build_tileset() -> Tileset:
    tiles = []
    for index in range(SHEET_COLUMNS * SHEET_ROWS):
        if index < len(FACING_ORDER):
            facing = FACING_ORDER[index]
            # Empty values are flags. TileZed writes "CanBreak =" with nothing
            # after the equals sign, and the game treats that as "yes".
            tiles.append(
                TileDef(
                    {
                        "BlocksPlacement": "",
                        "CanBreak": "",
                        "ContainerCapacity": CAPACITY,
                        "CustomName": "Sorter Crate",
                        "Facing": facing,
                        "container": "crate",
                        "solid": "",
                    }
                )
            )
        else:
            tiles.append(TileDef({}))
    return Tileset(
        name=TILESET_NAME,
        image_source=TILESET_NAME + ".png",
        columns=SHEET_COLUMNS,
        rows=SHEET_ROWS,
        tileset_id=TILESET_INDEX,
        tiles=tiles,
    )


def png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def pack_sheet(sheet: Image.Image) -> bytes:
    """Put the four painted cells on one atlas page, untrimmed.

    Leaving the cell whole (offset 0,0 and frame 128x256) means a new sheet
    with the same cell size lines up without anyone recomputing a trim box.
    """

    page = Image.new("RGBA", (PAGE_SIZE, PAGE_SIZE), (0, 0, 0, 0))
    entries = []
    for index in range(len(FACING_ORDER)):
        col = index % SHEET_COLUMNS
        row = index // SHEET_COLUMNS
        cell = sheet.crop(
            (col * CELL_W, row * CELL_H, (col + 1) * CELL_W, (row + 1) * CELL_H)
        )
        x = index * CELL_W
        y = 0
        page.paste(cell, (x, y))
        entries.append(
            PackEntry(
                name=sprite_name(index),
                x=x,
                y=y,
                w=CELL_W,
                h=CELL_H,
                ox=0,
                oy=0,
                fx=CELL_W,
                fy=CELL_H,
            )
        )
    page_png = png_bytes(page)
    return encode_pack([PackPage(name="pzsorter_crate0", png=page_png, entries=entries)])


def draw_poster(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (42, 36, 30, 255))
    draw = ImageDraw.Draw(image)
    margin = int(size * 0.08)
    draw.rectangle((margin, margin, size - margin, size - margin), fill=(112, 84, 54, 255), outline=(214, 168, 42, 255), width=max(2, size // 32))
    stripe_top = int(size * 0.42)
    stripe_bot = int(size * 0.58)
    draw.rectangle((margin, stripe_top, size - margin, stripe_bot), fill=(214, 168, 42, 255))
    title = _font(max(14, size // 9))
    small = _font(max(10, size // 16))
    _text_center(draw, (size / 2, size * 0.30), "PZSorter", title, (245, 236, 220, 255))
    _text_center(draw, (size / 2, size * 0.50), "TEMP", title, (40, 32, 24, 255))
    _text_center(draw, (size / 2, size * 0.74), "placeholder", small, (245, 236, 220, 255))
    return image


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def generate_placeholders() -> None:
    faces = [draw_placeholder_face(facing) for facing in FACING_ORDER]
    sheet = assemble_sheet(faces)
    for index, face in enumerate(faces):
        write_png(face_path(TEX_2X, index), face)
        write_png(face_path(TEX_1X, index), halve_nearest(face))
    write_png(sheet_path(TEX_2X), sheet)
    write_png(sheet_path(TEX_1X), halve_nearest(sheet))
    write_png(POSTER_PATH, draw_poster(256))
    write_png(ICON_PATH, draw_poster(64))


def sheet_from_faces() -> Image.Image:
    faces = []
    for index in range(len(FACING_ORDER)):
        path = face_path(TEX_2X, index)
        with Image.open(path) as image:
            faces.append(image.convert("RGBA").copy())
    sheet = assemble_sheet(faces)
    write_png(sheet_path(TEX_2X), sheet)
    small_faces = [halve_nearest(face) for face in faces]
    write_png(sheet_path(TEX_1X), halve_nearest(sheet))
    for index, face in enumerate(small_faces):
        write_png(face_path(TEX_1X, index), face)
    return sheet


def load_sheet() -> Image.Image:
    with Image.open(sheet_path(TEX_2X)) as image:
        return image.convert("RGBA").copy()


def write_game_files(sheet: Image.Image) -> None:
    tileset = build_tileset()
    TILES_PATH.parent.mkdir(parents=True, exist_ok=True)
    TILES_PATH.write_bytes(encode_tiles([tileset]))
    TILES_TEXT_PATH.write_text(write_tiles_text(tileset), encoding="utf-8")
    PACK_PATH.parent.mkdir(parents=True, exist_ok=True)
    PACK_PATH.write_bytes(pack_sheet(sheet))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build PZSorter crate tiles.")
    parser.add_argument(
        "--placeholders",
        action="store_true",
        help="Redraw the temporary crate art, then pack it.",
    )
    parser.add_argument(
        "--from-faces",
        action="store_true",
        help="Rebuild the sheet from the four 2x face PNGs, then pack it.",
    )
    args = parser.parse_args()
    if args.placeholders and args.from_faces:
        parser.error("pick one of --placeholders or --from-faces")
    if args.placeholders:
        generate_placeholders()
        sheet = load_sheet()
    elif args.from_faces:
        sheet = sheet_from_faces()
    else:
        sheet = load_sheet()
    if sheet.size != (SHEET_W, SHEET_H):
        raise SystemExit(
            "2x sheet is %s, expected %sx%s. The real art has to use the same grid."
            % (sheet.size, SHEET_W, SHEET_H)
        )
    write_game_files(sheet)
    print("wrote %s" % TILES_PATH.relative_to(ROOT))
    print("wrote %s" % PACK_PATH.relative_to(ROOT))


if __name__ == "__main__":
    main()
