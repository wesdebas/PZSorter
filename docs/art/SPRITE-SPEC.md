# Sorter Crate sprite spec

The final crate art is in. It is a wooden crate, a metal sheet screwed on as a drop slot, a yellow stripe, a branching-arrow mark, and a hanging name tag. `docs/images/sorter-crate-concept.jpg` is that look. Do not rename the files listed at the bottom.

Researched against Build **42.21**, the current stable build. Sources are cited. Where a Build 42 source and an older guide disagree, that is called out.

## Tile size

**Draw each cell at 128×256 pixels.** That is the 2× cell, and 2× is the size the game draws 1:1 at the default texture scale.

| | Build 41 | Build 42 |
|---|---|---|
| World cell (map geometry) | 300×300 squares | 256×256 squares |
| Block inside a cell | 10×10 | 8×8 |
| Sprite cell at 2× (the default) | 128×256 | 128×256 |
| Sprite cell at 1× | 64×128 | 64×128 |

Build 42 changed the map grid (cells and blocks). It did not change the sprite cell. A 128×256 cell is still the right "2×" drawing, and 64×128 is the "1×" drawing.

Sources:

- PZwiki, [Adding new tiles](https://pzwiki.net/wiki/Adding_new_tiles). A sprite's maximum size is 128×256. Sheets are typically 1024×2048 or 1024×4096, which is 8 cells across. The page says 2× textures are the default and are double the 1× textures. The page also carries a banner that the current stable version is 42.21 and the page may be inaccurate, so it is not the only source used here.
- HydeCo, [Project Zomboid B42 Engine Notes for Modders](https://hydecogames.com/tools/mapformats/), "Shipping a tileset". A sprite whose recorded canvas is 128×256 draws 1:1 when the game is at tile scale 2. A 64×128 canvas is scaled up with a blurry filter. The same notes say the official TileZed tools ship a 2× config with 128×256 cells. Measure opaque pixels at alpha above 128 if you trim: vanilla drop shadows sit at alpha 1–32 and will inflate a trim box.
- [libpzmap glossary](https://docs.rs/libpzmap/latest/libpzmap/glossary/index.html) and its [version table](https://docs.rs/libpzmap/latest/src/libpzmap/build/versions.rs.html). Build 42 cells are 256 squares and blocks are 8×8. Build 41 cells are 300 and blocks are 10×10. That write-up is about map geometry, not sprite pixels.
- The Indie Stone staff, [forum thread on the double-sized textures setting](https://theindiestone.com/forums/topic/70291-double-sized-textures-setting-break-some-custom-tiles-mod/). If a mod ships no 1× art, turning **Double sized textures** off makes custom tiles blow up, vanish, or overlap. Only the mod author can add the 1× set.

The floor diamond sits in the **bottom** 128×64 of the 128×256 cell. One storey of wall above that diamond is the other 192 pixels. A crate is much shorter than a storey: keep it sitting on the diamond, not floating in the empty space at the top of the cell. The final art uses this diamond:

- North corner of the floor: (64, 192)
- East corner: (128, 224)
- South corner: (64, 256)
- West corner: (0, 224)

North is the top-right of the screen and west is the top-left, in the game's isometric view ([PZwiki: Tile properties](https://pzwiki.net/wiki/Tile_properties), "Directions").

## Facings

A crate the player can rotate needs **four** cells, one per facing. The letters are the tile property `Facing`, and they are also the `face` blocks in the entity script.

| Cell index | Column, row | Sprite name | Facing | Entity face |
|---|---|---|---|---|
| 0 | 0, 0 | `pzsorter_crate_01_0` | E | `face E` |
| 1 | 1, 0 | `pzsorter_crate_01_1` | S | `face S` |
| 2 | 2, 0 | `pzsorter_crate_01_2` | W | `face W` |
| 3 | 3, 0 | `pzsorter_crate_01_3` | N | `face N` |

Numbering starts at 0 in the top-left cell and walks right, then down. That is the rule on [Adding new tiles](https://pzwiki.net/wiki/Adding_new_tiles) (`lighting_outdoor_01_0` is the first cell).

The facing order is confirmed in game: cell 0 is East, cell 1 is South, cell 2 is West, and cell 3 is North. Do not rename the files or swap the cells.

That order matches the sources used while the sheet was still a placeholder:

- The public [pztool](https://github.com/guspuffygit/project-zomboid-tile-cli) example puts `Facing = E` on cell `xy = 0,0`, which is index 0.
- Vanilla's branch stool uses the next index for the next facing: `crafted_04_112` is Facing E and `crafted_04_113` is Facing S ([PZwiki: Branch Stool](https://pzwiki.net/wiki/Branch_Stool)).
- West then North continue that same clockwise step (E, S, W, N). A multi-tile wardrobe on the wiki groups its cells as east, then west, then north, but those are two-cell-wide pieces, not four rotations of one crate, so they were not copied as the order.

Vanilla's own built wooden crate only defines `face S` (one sprite, `carpentry_01_19`). It does not rotate. We still ship four faces because the build menu rotates an entity that defines more than one `face` block. The bed example on the Indie Stone forums shows the shape: a `face S` block and a `face E` block, each with a `row` of sprite names ([how to add new constructions](https://theindiestone.com/forums/topic/87969-42123-how-to-add-new-constructions/)).

East (cell 0) and South (cell 1) show the front of the crate. Facings 2 (W) and 3 (N) show the crate's back on purpose. The camera only sees the south-west and south-east sides of a box, so those two facings are the back, not a swapped pair of cells.

## File format

- PNG, with a real alpha channel. No coloured backdrop, no white matte.
- The 2× sheet is **1024×2048**: 8 columns by 8 rows of 128×256. That is the usual TileZed sheet. Other sizes cause trouble when a texture pack is built ([Adding new tiles](https://pzwiki.net/wiki/Adding_new_tiles)).
- Only cells 0–3 are painted. Cells 4–63 stay fully transparent. They are reserved so the sheet size never has to change.
- File names are lowercase. The game's pack lookup lowercases file names; sprite names are matched with case intact (HydeCo, "Shipping a tileset").
- Also keep a 1× set at half size, **nearest-neighbour**, not filtered. The 1× sheet is 512×1024, and each 1× cell is 64×128. HydeCo warns that a linear scale blurs, and then the game may scale it a second time and draw the crate huge.

We pack the **2×** cells into the `.pack` the game loads, each with its frame recorded as 128×256 and **not trimmed**. An untrimmed cell means your new painting lines up on the same diamond without anyone recomputing offsets. HydeCo notes that a trimmed sprite stores an offset back into its 128×256 canvas, and a wrong offset makes the crate float. Leaving the cell whole avoids that.

The 1× PNGs are in the repo so a 1× pack can be built if playing with **Double sized textures** off looks wrong (the forum note above). They are not inside the `.pack` we ship: one sprite name cannot be two sizes in the same pack. That is an open check for the in-game test.

## How the game loads it

Two binary files, both declared in `Contents/mods/PZSorter/42/mod.info`:

```
pack=pzsorter_crate
tiledef=pzsorter_crate 7311
```

| What | Path | Who reads it |
|---|---|---|
| Texture pack | `Contents/mods/PZSorter/common/media/texturepacks/pzsorter_crate.pack` | The game, because of `pack=` |
| Tile definitions | `Contents/mods/PZSorter/common/media/pzsorter_crate.tiles` | The game, because of `tiledef=` |
| Readable copy of the properties | `Contents/mods/PZSorter/common/media/pzsorter_crate.tiles.txt` | People. The game does **not** load this. |

The `.tiles` file is TileZed's `tdef` binary (magic `tdef`, version 1). The `.pack` file is TileZed's `PZPK` binary (magic `PZPK`, version 1). Layout, including the newline-terminated strings in `.tiles` and the length-prefixed strings in `.pack`, is the one documented by [pztool](https://github.com/guspuffygit/project-zomboid-tile-cli). `tools/pztile.py` writes both.

Two different numbers, easy to mix up (HydeCo):

- **7311** in `mod.info` is the mod tiledef id. Legal mod ids are 100–8189. 0–99 are reserved for the game. Two enabled mods with the same id collide and the game skips the whole file ([PZwiki: Tiledefs used by mods](https://pzwiki.net/wiki/Tiledefs_used_by_mods), [mod.info field](https://pz-wiki-modding.github.io/PZ-API-Docs/scripts/root_files/modinfo.html)). 7311 was picked because it is inside that range. If `console.txt` says the tiledef collided, change the number in `mod.info` only.
- **1** inside `pzsorter_crate.tiles` is the sheet's index in that file. It must be from 1 to 512. It is not 7311. Using the mod id here makes the game throw `invalid tileset number` and then skip every later mod's tiles too.

Sprite names the scripts use:

- `pzsorter_crate_01_0` through `pzsorter_crate_01_3`
- The tileset name is `pzsorter_crate_01`. The sprite name is that, an underscore, and the cell index.

The entity that places the crate is `Contents/mods/PZSorter/42/media/scripts/PZSorter_entities.txt`. Each `face` block's `row` is one of those four sprite names. A sprite name can belong to only one entity. Reusing a vanilla sprite that some other entity already claims aborts the world load with `Sprite is duplicate` (HydeCo, world objects). That is why this crate has its own sheet instead of borrowing `carpentry_01_19`.

### Properties on each of the four cells

| Property | Value | Why |
|---|---|---|
| `container` | `crate` | Loot icon and container behaviour |
| `ContainerCapacity` | `50` | The 50 capacity. The chunk loader reads this. A Lua-only capacity resets on reload (HydeCo, "Containers") |
| `CustomName` | `Sorter Crate` | Fallback label before the player's name is applied |
| `Facing` | `E`, `S`, `W`, or `N` | Which way this cell points |
| `CanBreak` | (flag, no value) | A sledge can break it, like other crates |
| `BlocksPlacement` | (flag) | Another build cannot occupy the same square |
| `solid` | (flag) | You walk around it, not through it |

`IsMoveAble` is set, and `CustomItem` is `PZSorter.SorterCrate`, so vanilla pickup creates that item instead of a nameless moveable. The item carries the crate's saved name and links. `ForceSingleItem` keeps the four facings from being treated as one multi-tile object. Dismantle is still how you take it apart for materials.

There is no `CanScrap`. Vanilla scrap returns whatever the material table says (nails, for wood), and it would not honour "always return the metal sheet". Dismantle is handled by our own menu.

### Depth (so the crate does not draw on top of the player)

Build 42's per-pixel depth is a PNG, not the old `tileGeometry.txt` boxes. HydeCo, "Depth":

- The game reads `common/media/depthmaps/DEPTH_<tileset>.png`.
- One 128×256 cell per slot, **8 columns**, so the image is 1024 wide. Blue/255 is the depth. Alpha 0 means "no depth here".
- It loads that folder only when `common/media/tileGeometry.txt` exists.
- A sprite with no depth cell falls back to `DEPTH_whole_tile.png`, the whole-square cube, and draws over anyone standing on its own square.

The final art does **not** ship a depth map, so it still uses that cube. A later change can add:

- `Contents/mods/PZSorter/common/media/tileGeometry.txt` (it can be almost empty; it is the switch that turns depth maps on)
- `Contents/mods/PZSorter/common/media/depthmaps/DEPTH_pzsorter_crate_01.png`

Do not borrow another sprite's depth cell unless the silhouette matches. A borrowed cell clips where the paintings differ (HydeCo).

## Files

The paths below are the final art. To change the painting later, draw into the same pixels, then rebuild the pack. From the repo root:

```
python3 tools/build_tiles.py
```

That reads the 2× sheet and rewrites the `.tiles` and the `.pack`. No Lua changes.

Or replace the four face files and run:

```
python3 tools/build_tiles.py --from-faces
```

That pastes the faces back into the sheet (cell 0 at the top left, then 1, 2, 3) and packs it.

`--placeholders` redraws the old TEMP art. Do not run it. The final art is already in.

### Paths

2× (this is the set the game pack is built from):

- `Contents/mods/PZSorter/common/media/textures/pzsorter/2x/pzsorter_crate_01.png` — the 1024×2048 sheet
- `Contents/mods/PZSorter/common/media/textures/pzsorter/2x/faces/pzsorter_crate_01_0.png` — East, 128×256
- `Contents/mods/PZSorter/common/media/textures/pzsorter/2x/faces/pzsorter_crate_01_1.png` — South
- `Contents/mods/PZSorter/common/media/textures/pzsorter/2x/faces/pzsorter_crate_01_2.png` — West
- `Contents/mods/PZSorter/common/media/textures/pzsorter/2x/faces/pzsorter_crate_01_3.png` — North

1× (the half-size files from the final art):

- `Contents/mods/PZSorter/common/media/textures/pzsorter/1x/pzsorter_crate_01.png` — 512×1024
- `Contents/mods/PZSorter/common/media/textures/pzsorter/1x/faces/pzsorter_crate_01_0.png` through `_3.png` — 64×128

Those 1× PNGs are the files from the art drop. They are a filtered scale of the 2× sheet, not a nearest-neighbour rebuild. The `.pack` is still built from the 2× sheet.

Game files the script rewrites (do not hand-edit):

- `Contents/mods/PZSorter/common/media/texturepacks/pzsorter_crate.pack`
- `Contents/mods/PZSorter/common/media/pzsorter_crate.tiles`
- `Contents/mods/PZSorter/common/media/pzsorter_crate.tiles.txt`

`poster.png` and `icon.png` next to `mod.info` are the mod-list images, not the world tile. They are placeholders too. The Workshop `preview.png` is a later step and is not part of this swap.

## Uncertainties to confirm on 42.21

- Whether 42.21 still requires a separate 1× pack when Double sized textures is off. The 1× PNGs are in the repo. The shipped `.pack` is 2× only, which matches the default setting.
- The final art has no depth map, so it uses the whole-tile cube.
- `tiledef` 7311 must not already be taken by another enabled mod. The community list is [Tiledefs used by mods](https://pzwiki.net/wiki/Tiledefs_used_by_mods). A collision is a one-line change in `mod.info`.
