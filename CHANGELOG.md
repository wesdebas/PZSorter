# Changelog

All notable changes to PZSorter are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [semantic versions](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-04

### Added

- Right-click a crate, shelf, counter, fridge, or freezer and choose **Assign to Sorter**. Sorters in range are listed. A sorter that is nearby but outside the sandbox square is greyed out, and the tooltip says "Too far from [Name]".
- A container belongs to one sorter. If it already belongs to one, the menu offers **Move to [Name]** and **Unassign from [Name]**.
- A fridge/freezer combo is two rows. Each row is named from the container type, like "Fridge 1" or "Freezer 1".
- **Open Sorter** on the crate opens a panel. Each linked container shows its name, how full it is, and a status dot. Green is in range, grey is out of range, red says "Missing" when that container is gone. Remove unassigns it. Linked containers glow while the panel is open, and hovering a row glows only that one.
- Inside a safehouse, only members can assign or unassign. Outside a safehouse, anyone can.
- Pick up a Sorter Crate from the move menu. It has to be empty. The item keeps the crate's name, id, and links, and placing it back does not ask for a name again. Containers it owns stay assigned while it is in your inventory.

## [0.1.0] - 2026-11-03

### Fixed

- The Sorter Crate shows up in the build menu. The menu needs an entity style (`ES_PZSorter_SorterCrate`) for the name and icon. Search for "Sorter" under Carpentry, Furniture.
- Right-click no longer crashes. Dismantle asks the inventory with an ItemTag, not a string.
- The loot window uses the crate's name (or "Sorter Crate"), not the generic "Crate".
- Placing a crate opens the name box. Rename is on the right-click menu as well.
- The build-menu icon is a real texture, so the log no longer warns that "default" is missing.
- Single player was skipping every save and every name box. On 42.21, isClient() and isServer() are both false there, and the old guards treated that as "do nothing". Naming, Rename, and Dismantle now run directly in that case. A vanilla rename in the loot window is kept.
- A name you type is kept. The automatic "Sorter N" still on the container is not treated as a rename from the loot window.
- The name box opens once for a crate. Single player no longer sends OpenName after opening the box itself.
- The suggested name is the lowest "Sorter N" that no existing crate is using. That list is kept across a reload, and dismantling a crate frees its number.

### Added

- A Sorter Crate you can build from the Furniture page once you have Carpentry 1, 4 Planks, 10 Screws, 1 Small Metal Sheet, a Hammer, and a Screwdriver. The tools are not used up. The crate holds 50.
- A name box when you place a crate. It suggests "Sorter 1", then "Sorter 2", and so on. A name has to be 1 to 24 characters. The name shows when you point at the crate, and it is still there after you save, quit, and load.
- Sandbox option **Sorter range**, from 20 to 30 tiles, default 20. The area is a square counted from the crate, on the crate's floor and one floor above and below.
- Dismantle on the crate's right-click menu. You need a hammer and a saw. Some of the planks and screws come back, the way vanilla furniture does, and the Small Metal Sheet always comes back. Items that were inside drop on the ground.
- The final crate art is in. Cells 0 to 3 face East, South, West, and North. Facings 2 (W) and 3 (N) show the crate's back on purpose.
- The crate art was redrawn at the game's isometric angle.
