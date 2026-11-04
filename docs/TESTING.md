# Testing PZSorter

This is the install and the checks for the assign-containers branch. Building and naming from step 1 are still here. This branch adds assigning containers and the sorter panel. Filters and Sort are not in yet.

Target game: Project Zomboid **Build 42.21** (the current stable build). The mod is marked Build 42 only.

## One-time setup (Windows Command Prompt)

```
cd C:\AI\Projects
git clone https://github.com/wesdebas/PZSorter.git
mklink /J "%USERPROFILE%\Zomboid\Workshop\PZSorter" "C:\AI\Projects\PZSorter"
```

The `mklink /J` line makes a folder link, so the game sees the repo inside its Workshop folder without a second copy. It does not need an administrator. Do not also subscribe to PZSorter on Steam, and do not keep another copy in `Zomboid\mods`. Two copies of the same mod clash.

## Load this branch

```
cd /d C:\AI\Projects\PZSorter
git fetch
git checkout feature/assign-containers
git pull
pause
```

Then start Project Zomboid. In **Mods**, enable **PZSorter**. Start a fresh **Sandbox** game. The PZSorter page is where Sorter range lives.

Debug mode is optional. Add `-debug` to the Steam launch options if you want to spawn planks, screws, a small metal sheet, a hammer, a saw, and Carpentry levels quickly. The first check (recipe greyed out without materials or Carpentry 1) needs **Build cheat turned off** in the debug Cheats panel. While Build cheat is on, the log says materials are not required, so that check cannot fail.

If something breaks, send `%USERPROFILE%\Zomboid\console.txt`.

To go back to the last merged version: `git checkout main` then `git pull`.

## What you are checking

The final crate art is in. It is the wooden crate with the metal drop slot, the yellow stripe, and the branching arrow. Facings 2 (W) and 3 (N) show the crate's back on purpose. That is not a mix-up of the four cells.

Dismantle needs a **hammer and a saw** (a hacksaw is fine). Building needs a hammer and a screwdriver. Those are not the same pair of tools.

Planks and screws only sometimes come back. At Carpentry 1 that is often very little. The Small Metal Sheet comes back every time.

## Where to find it

Open **Build** (the menu for objects you place in the world). It is not in the item crafting menu.

Search for **Sorter**. It is listed as **Sorter Crate**, under **Carpentry**, in the **Furniture** category. With no materials or no Carpentry 1 it is greyed out, but the search still finds it.

If the search finds nothing, check `console.txt` for `Cannot find entity ui info: ES_PZSorter_SorterCrate`. That line means the build-menu name did not load.

## Checklist

- [ ] Search the build menu for "Sorter". Sorter Crate is there, under Carpentry, Furniture.
- [ ] Without the materials or without Carpentry 1, the Sorter Crate recipe is greyed out. It is on the Furniture page.
- [ ] With 4 Planks, 10 Screws, 1 Small Metal Sheet, a Hammer, a Screwdriver, and Carpentry 1, build the crate. The hammer and the screwdriver are still in your inventory. The materials are gone.
- [ ] The name box shows "Sorter 1". Try an empty name. Try a 25-character name. Both stay in the box and tell you why. Then accept a normal name.
- [ ] Point at the crate. The name you typed shows. Put items in. The capacity is 50.
- [ ] Build a second crate. The box suggests "Sorter 2". A later crate takes the lowest "Sorter N" that no crate is still using. Save, quit, and load, then build another: it must not offer a number a crate you can still see is already using.
- [ ] Save, quit to the desktop, and load. Both names are still there.
- [ ] Dismantle one crate (right-click, Dismantle, with a hammer and a saw). The Small Metal Sheet comes back. Some or none of the planks and screws come back. Items that were inside are on the ground, not deleted.
- [ ] On the Sandbox page, Sorter range is there, from 20 to 30, and a new game starts at 20.
- [ ] `console.txt` has no PZSorter errors. A line that says the crate save data loaded is expected.

Rotate the crate while placing it if the build menu lets you. East and South show the front. Facings 2 (W) and 3 (N) show the back on purpose.

## Step 2 checklist

Build two Sorter Crates a few tiles apart and name them, for example "Home" and "Farm". You also need an ordinary container (a crate, a counter, a shelf). A fridge with a freezer is useful but not required. Sorter range on the sandbox page stays at 20 unless a check says otherwise.

- [ ] Right-click the ordinary container. **Assign to Sorter** lists Home and Farm when both are within 20 tiles. Pick Home.
- [ ] Right-click that container again. The menu offers **Unassign from Home**, and **Move to Farm** instead of a second assign. Move it. Open Sorter on Home: the container is gone. Open Sorter on Farm: it is there.
- [ ] Put a container just inside 20 tiles of a sorter, and be sure another sorter is 21 or more tiles away (count the tiles; a diagonal counts the same as straight). The far sorter is greyed out. Its tooltip says "Too far from [Name]". One floor up or down still counts as in range. Two floors does not show as a choice.
- [ ] On a fridge/freezer, Assign to Sorter has two entries, one for each part. Assigning one does not assign the other.
- [ ] Two sorters do not share a container. After the move above, only Farm lists it.
- [ ] Open Sorter. The header is the crate's name. The row shows the name (Fridge 1, Crate 1, and so on), a fill bar, and a green dot. Put something in the container: the bar moves. Sort and Preview are visible and cannot be clicked.
- [ ] While the panel is open, the linked container glows. Hover the row: only that container glows. Close the panel: the glow is gone.
- [ ] Pick up or destroy the linked container. Its row turns red and says Missing. It stays until Remove.
- [ ] Remove, or Unassign from the right-click menu. The row is gone. That container can be assigned again.
- [ ] Save, quit to the desktop, and load. The assignment is still there.
- [ ] If you have a safehouse: a member can assign. Someone who is not a member gets "Only safehouse members can use this sorter." Outside a safehouse, anyone can. Skip this if the test save has no safehouse.
- [ ] `console.txt` has no PZSorter errors. Lines that say the assign menu, `running Assign directly`, and `assigned` are expected. A grey sorter that still runs is a bug: the log would say `link refused, outside sorter range`.

## Pickup

The crate has to be empty. Vanilla pickup is the same menu you use on a chair or a crate that can be moved.

- [ ] Put an item in the Sorter Crate. Pick it up. The crate stays, and you get a message to empty it. The log says `pickup refused, crate is not empty`.
- [ ] Take the item out. Pick the crate up. It leaves the world and a Sorter Crate item is in your inventory. The log says `pickup stored name=` and the link count.
- [ ] While it is in your inventory, a container it owned still offers Unassign from that name, and does not offer Assign to that same crate.
- [ ] Place the item somewhere else. Press R (or the controller rotate) before you click. The log once says `rotate faces found=4` and lists `pzsorter_crate_01_3`, `_2`, `_1`, and `_0`. Each press cycles North, West, South, East. The placed crate matches the ghost. The log says `place facing=N sprite=pzsorter_crate_01_3` for north, and the matching sprite for the other three. The name box does not open. The log also says `place restored name=` with the same name and the same link count. On load, four lines `sprite props pzsorter_crate_01_0` through `_3` should show Facing, GroupName, CustomName, IsMoveAble, and the offsets.
- [ ] Open Sorter. The header is the old name. The rows are the same containers. One that is now outside the sandbox square has a grey Out of range dot, not Missing.
- [ ] Save, quit to the desktop, and load. The name, the rows, and the dots are still right.
