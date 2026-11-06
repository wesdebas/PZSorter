"""Check the committed crate art against the rules the game will enforce.

This does not start Project Zomboid. It reads the .tiles and .pack files and
the text files that point at them, and fails if a name, a facing, or the
capacity drifted apart.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_tiles import (  # noqa: E402
    CELL_H,
    CELL_W,
    FACING_ORDER,
    ICON_PATH,
    PACK_PATH,
    POSTER_PATH,
    SHEET_H,
    SHEET_W,
    TILESET_INDEX,
    TILESET_NAME,
    TILES_PATH,
    face_offsets,
    face_path,
    sheet_path,
    sprite_name,
    TEX_1X,
    TEX_2X,
)
from pztile import decode_pack, decode_tiles  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MOD_INFO = ROOT / "Contents" / "mods" / "PZSorter" / "42" / "mod.info"
ENTITY = ROOT / "Contents" / "mods" / "PZSorter" / "42" / "media" / "scripts" / "PZSorter_entities.txt"
XUI = ROOT / "Contents" / "mods" / "PZSorter" / "42" / "media" / "scripts" / "PZSorter_xuiSkin.txt"
SANDBOX = ROOT / "Contents" / "mods" / "PZSorter" / "42" / "media" / "sandbox-options.txt"
CONFIG = ROOT / "Contents" / "mods" / "PZSorter" / "42" / "media" / "lua" / "shared" / "PZSorter" / "Config.lua"


def fail(message: str) -> None:
    raise SystemExit("tile check: " + message)


def main() -> None:
    tilesets = decode_tiles(TILES_PATH.read_bytes())
    if len(tilesets) != 1:
        fail("expected one tileset, found %s" % len(tilesets))
    tileset = tilesets[0]
    if tileset.name != TILESET_NAME:
        fail("tileset name %s" % tileset.name)
    if tileset.tileset_id != TILESET_INDEX:
        fail("tileset index %s is not %s (this is the in-file index, not mod.info)" % (tileset.tileset_id, TILESET_INDEX))
    if tileset.columns != 8 or tileset.rows != 8:
        fail("sheet grid is %sx%s" % (tileset.columns, tileset.rows))
    if len(tileset.tiles) != 64:
        fail("tile count %s" % len(tileset.tiles))

    for index, facing in enumerate(FACING_ORDER):
        props = tileset.tiles[index].properties
        if props.get("Facing") != facing:
            fail("cell %s facing is %s, expected %s" % (index, props.get("Facing"), facing))
        if props.get("ContainerCapacity") != "50":
            fail("cell %s capacity is %s" % (index, props.get("ContainerCapacity")))
        if props.get("container") != "crate":
            fail("cell %s is not a crate container" % index)
        if "CanBreak" not in props or "solid" not in props:
            fail("cell %s is missing CanBreak or solid" % index)
        # Pickup creates PZSorter.SorterCrate. Without IsMoveAble and
        # CustomItem the move action plays and then creates no item.
        if "IsMoveAble" not in props:
            fail("cell %s is not moveable" % index)
        if props.get("CustomItem") != "PZSorter.SorterCrate":
            fail("cell %s CustomItem is %s" % (index, props.get("CustomItem")))
        if props.get("CustomName") != "Crate":
            fail("cell %s CustomName is %s" % (index, props.get("CustomName")))
        if props.get("GroupName") != "Sorter":
            fail("cell %s GroupName is %s" % (index, props.get("GroupName")))
        if "ForceSingleItem" in props:
            fail("cell %s is ForceSingleItem, so the place cursor will not rotate it" % index)
        # getFaces() builds pzsorter_crate_01_<spriteID + offset>. Missing
        # offsets make hasFaces() false, so R never changes the ghost.
        expected_offsets = face_offsets(facing)
        for key, value in expected_offsets.items():
            if props.get(key) != value:
                fail("cell %s %s is %s, expected %s" % (index, key, props.get(key), value))
        for other in ("N", "W", "S", "E"):
            key = "%soffset" % other
            if other != facing and key not in expected_offsets:
                fail("cell %s missing computed %s" % (index, key))

    for index in range(len(FACING_ORDER), 64):
        if tileset.tiles[index].properties:
            fail("empty cell %s has properties; only the first four cells are the crate" % index)

    pages = decode_pack(PACK_PATH.read_bytes())
    if len(pages) != 1:
        fail("expected one pack page")
    page = pages[0]
    if page.name != "pzsorter_crate0":
        fail("pack page name %s" % page.name)
    names = [entry.name for entry in page.entries]
    expected_names = [sprite_name(i) for i in range(len(FACING_ORDER))]
    if names != expected_names:
        fail("pack sprites %s" % names)
    image = Image.open(io.BytesIO(page.png))
    if image.size != (1024, 1024):
        fail("pack page is %s, expected 1024x1024" % (image.size,))
    for entry in page.entries:
        if (entry.fx, entry.fy) != (CELL_W, CELL_H):
            fail("%s frame is %sx%s, expected 128x256" % (entry.name, entry.fx, entry.fy))
        if (entry.ox, entry.oy) != (0, 0):
            fail("%s is trimmed; placeholder cells are packed whole" % entry.name)
        if (entry.w, entry.h) != (CELL_W, CELL_H):
            fail("%s rect is %sx%s" % (entry.name, entry.w, entry.h))
        cell = image.crop((entry.x, entry.y, entry.x + entry.w, entry.y + entry.h))
        if cell.getextrema()[3][1] == 0:
            fail("%s is fully transparent" % entry.name)

    sheet = Image.open(sheet_path(TEX_2X))
    if sheet.size != (SHEET_W, SHEET_H):
        fail("2x sheet is %s" % (sheet.size,))
    small = Image.open(sheet_path(TEX_1X))
    if small.size != (SHEET_W // 2, SHEET_H // 2):
        fail("1x sheet is %s" % (small.size,))
    for index in range(len(FACING_ORDER)):
        face = Image.open(face_path(TEX_2X, index))
        if face.size != (CELL_W, CELL_H):
            fail("2x face %s is %s" % (index, face.size))
        face1 = Image.open(face_path(TEX_1X, index))
        if face1.size != (CELL_W // 2, CELL_H // 2):
            fail("1x face %s is %s" % (index, face1.size))

    mod_info = MOD_INFO.read_text(encoding="utf-8")
    for line in (
        "id=PZSorter_wd",
        "author=wesdebas",
        "modversion=0.2.0",
        "versionMin=42.0",
        "pack=pzsorter_crate",
        "tiledef=pzsorter_crate 7311",
    ):
        if line not in mod_info.splitlines():
            fail("mod.info is missing %s" % line)

    entity = ENTITY.read_text(encoding="utf-8")
    # Vanilla chair and window (42.21 dumps) use these exact recipe fields.
    # Item tags are namespaced (base:hammer). The build-menu tags are not.
    for line in (
        "category = Furniture,",
        "Tags = Carpentry;Furniture,",
        "Tooltip = Tooltip_PZSorter_SorterCrate,",
        "entityStyle = ES_PZSorter_SorterCrate,",
        "OnCreate = PZSorter.OnSpriteCreate,",
        "tags[base:hammer]",
        "tags[base:screwdriver]",
    ):
        if line not in entity:
            fail("entity script is missing %s" % line)
    if "ToolTip =" in entity:
        fail("entity script uses ToolTip; 42.21 ignores that spelling")
    skin = XUI.read_text(encoding="utf-8")
    for line in (
        "module Base",
        "xuiSkin default",
        "entity ES_PZSorter_SorterCrate",
        "DisplayName = EC_PZSorter_SorterCrate,",
        "LuaWindowClass = ISEntityWindow,",
        "Icon = Build_PZSorterCrate,",
    ):
        if line not in skin:
            fail("xui skin is missing %s" % line)
    for index, facing in enumerate(FACING_ORDER):
        needle = "row = %s" % sprite_name(index)
        if needle not in entity:
            fail("entity script does not use %s for a row" % sprite_name(index))
        face_block = "face %s" % facing
        if face_block not in entity:
            fail("entity script has no %s" % face_block)

    sandbox = SANDBOX.read_text(encoding="utf-8")
    for line in ("VERSION = 1,", "type = integer,", "min = 20,", "max = 30,", "default = 20,"):
        if line not in sandbox:
            fail("sandbox options missing %s" % line)

    config = CONFIG.read_text(encoding="utf-8")
    if "CAPACITY = 50" not in config:
        fail("Config.lua capacity is not 50")
    for index in range(len(FACING_ORDER)):
        if sprite_name(index) not in config:
            fail("Config.lua does not name %s" % sprite_name(index))

    icon = ROOT / "Contents" / "mods" / "PZSorter" / "42" / "media" / "textures" / "Build_PZSorterCrate.png"
    if not icon.is_file():
        fail("missing build menu icon " + str(icon))
    if Image.open(POSTER_PATH).size != (256, 256):
        fail("poster.png is not 256x256")
    if Image.open(ICON_PATH).size != (64, 64):
        fail("icon.png is not 64x64")

    print("tile check ok")


if __name__ == "__main__":
    main()
