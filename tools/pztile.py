"""Read and write the two binary files Project Zomboid uses for tiles.

The game never reads a loose PNG as a world tile. It reads a texture pack
(.pack) and a tile-definition file (.tiles). Both are little-endian files
written by TileZed's Qt code. The layout implemented here matches the public
pztool notes and the pztool source (newline-terminated strings in .tiles,
length-prefixed strings in .pack):

https://github.com/guspuffygit/project-zomboid-tile-cli

This module is the only place those bytes are assembled, so a future art
swap rebuilds both files without anyone hand-editing binary.
"""

from __future__ import annotations

import io
import struct
from dataclasses import dataclass, field


def _i32(value: int) -> bytes:
    return struct.pack("<i", int(value))


def _newline_string(text: str) -> bytes:
    # TileZed writes these as Latin-1 bytes plus a newline. No length prefix.
    raw = text.encode("latin-1", errors="replace")
    return raw + b"\n"


def _length_string(text: str) -> bytes:
    raw = text.encode("latin-1", errors="replace")
    return _i32(len(raw)) + raw


@dataclass
class TileDef:
    """One cell on a tilesheet. Index 0 is the top-left cell."""

    properties: dict[str, str] = field(default_factory=dict)


@dataclass
class Tileset:
    name: str
    image_source: str
    columns: int
    rows: int
    # This id is the sheet's index INSIDE the file (1..512). It is not the
    # mod.info tiledef number. The game rejects anything outside 1..512.
    tileset_id: int
    tiles: list[TileDef]


def encode_tiles(tilesets: list[Tileset]) -> bytes:
    out = io.BytesIO()
    out.write(b"tdef")
    out.write(_i32(1))
    out.write(_i32(len(tilesets)))
    for tileset in tilesets:
        if not 1 <= tileset.tileset_id <= 512:
            raise ValueError(
                "tileset id %s is not between 1 and 512" % tileset.tileset_id
            )
        expected = tileset.columns * tileset.rows
        if len(tileset.tiles) != expected:
            raise ValueError(
                "%s has %s tiles, expected %s (%sx%s)"
                % (tileset.name, len(tileset.tiles), expected, tileset.columns, tileset.rows)
            )
        out.write(_newline_string(tileset.name))
        out.write(_newline_string(tileset.image_source))
        out.write(_i32(tileset.columns))
        out.write(_i32(tileset.rows))
        out.write(_i32(tileset.tileset_id))
        out.write(_i32(len(tileset.tiles)))
        for tile in tileset.tiles:
            # Qt's QMap writes keys in ascending order. Match that so a
            # TileZed round trip does not reshuffle the file.
            keys = sorted(tile.properties)
            out.write(_i32(len(keys)))
            for key in keys:
                out.write(_newline_string(key))
                out.write(_newline_string(tile.properties[key]))
    return out.getvalue()


def _read_i32(buf: io.BytesIO) -> int:
    raw = buf.read(4)
    if len(raw) != 4:
        raise ValueError("unexpected end of file")
    return struct.unpack("<i", raw)[0]


def _read_newline_string(buf: io.BytesIO) -> str:
    raw = bytearray()
    while True:
        b = buf.read(1)
        if not b:
            raise ValueError("unterminated string")
        if b == b"\n":
            return raw.decode("latin-1")
        raw.extend(b)


def _read_length_string(buf: io.BytesIO) -> str:
    n = _read_i32(buf)
    if n < 0:
        raise ValueError("negative string length")
    raw = buf.read(n)
    if len(raw) != n:
        raise ValueError("short string")
    return raw.decode("latin-1")


def decode_tiles(data: bytes) -> list[Tileset]:
    buf = io.BytesIO(data)
    magic = buf.read(4)
    if magic != b"tdef":
        raise ValueError("not a tdef file")
    version = _read_i32(buf)
    if version != 1:
        raise ValueError("unsupported tiles version %s" % version)
    count = _read_i32(buf)
    tilesets = []
    for _ in range(count):
        name = _read_newline_string(buf)
        image = _read_newline_string(buf)
        columns = _read_i32(buf)
        rows = _read_i32(buf)
        tileset_id = _read_i32(buf)
        tile_count = _read_i32(buf)
        tiles = []
        for _tile in range(tile_count):
            prop_count = _read_i32(buf)
            props = {}
            for _prop in range(prop_count):
                key = _read_newline_string(buf)
                value = _read_newline_string(buf)
                props[key] = value
            tiles.append(TileDef(props))
        tilesets.append(
            Tileset(name, image, columns, rows, tileset_id, tiles)
        )
    return tilesets


@dataclass
class PackEntry:
    name: str
    x: int
    y: int
    w: int
    h: int
    ox: int
    oy: int
    fx: int
    fy: int


@dataclass
class PackPage:
    name: str
    png: bytes
    entries: list[PackEntry]


def encode_pack(pages: list[PackPage]) -> bytes:
    out = io.BytesIO()
    out.write(b"PZPK")
    out.write(_i32(1))
    out.write(_i32(len(pages)))
    for page in pages:
        out.write(_length_string(page.name))
        out.write(_i32(len(page.entries)))
        # TileZed always writes this mask as 1. The game ignores it on read.
        out.write(_i32(1))
        for entry in page.entries:
            out.write(_length_string(entry.name))
            for value in (entry.x, entry.y, entry.w, entry.h, entry.ox, entry.oy, entry.fx, entry.fy):
                out.write(_i32(value))
        out.write(_i32(len(page.png)))
        out.write(page.png)
    return out.getvalue()


def decode_pack(data: bytes) -> list[PackPage]:
    buf = io.BytesIO(data)
    magic = buf.read(4)
    if magic != b"PZPK":
        raise ValueError("not a PZPK file")
    version = _read_i32(buf)
    if version != 1:
        raise ValueError("unsupported pack version %s" % version)
    count = _read_i32(buf)
    pages = []
    for _ in range(count):
        name = _read_length_string(buf)
        entry_count = _read_i32(buf)
        _read_i32(buf)  # mask
        entries = []
        for _entry in range(entry_count):
            entry_name = _read_length_string(buf)
            coords = [_read_i32(buf) for _i in range(8)]
            entries.append(PackEntry(entry_name, *coords))
        png_len = _read_i32(buf)
        png = buf.read(png_len)
        if len(png) != png_len:
            raise ValueError("short png")
        pages.append(PackPage(name, png, entries))
    return pages


def write_tiles_text(tileset: Tileset) -> str:
    """Human-readable copy of the tile properties.

    TileZed can export a .tiles.txt, but the game does not load that text.
    We keep it next to the binary so a person can see the capacity and the
    facing of each cell without a hex editor.
    """

    lines = [
        "version = 1",
        "tileset",
        "{",
        "    file = %s" % tileset.name,
        "    image = %s" % tileset.image_source,
        "    size = %s,%s" % (tileset.columns, tileset.rows),
        "    id = %s" % tileset.tileset_id,
    ]
    for index, tile in enumerate(tileset.tiles):
        if not tile.properties:
            continue
        col = index % tileset.columns
        row = index // tileset.columns
        lines.append("    // %s_%s  (column %s, row %s)" % (tileset.name, index, col, row))
        lines.append("    tile")
        lines.append("    {")
        lines.append("        xy = %s,%s" % (col, row))
        for key in sorted(tile.properties):
            value = tile.properties[key]
            if value == "":
                lines.append("        %s =" % key)
            else:
                lines.append("        %s = %s" % (key, value))
        lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)
