# Testing PZSorter

This is the install and the checks for the crate-and-naming branch. Sorting, assigning containers, and the filter tree are not in this branch.

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
git checkout feature/crate-and-naming
git pull
pause
```

Then start Project Zomboid. In **Mods**, enable **PZSorter**. Start a fresh **Sandbox** game. The PZSorter page is where Sorter range lives.

Debug mode is optional. Add `-debug` to the Steam launch options if you want to spawn planks, screws, a small metal sheet, a hammer, a saw, and Carpentry levels quickly.

If something breaks, send `%USERPROFILE%\Zomboid\console.txt`.

To go back to the last merged version: `git checkout main` then `git pull`.

## What you are checking

The crate art is a placeholder. It says TEMP in red, and the metal plate has a letter (E, S, W, or N) so you can see which way it is facing. The real art is not in this branch.

Dismantle needs a **hammer and a saw** (a hacksaw is fine). Building needs a hammer and a screwdriver. Those are not the same pair of tools.

Planks and screws only sometimes come back. At Carpentry 1 that is often very little. The Small Metal Sheet comes back every time.

## Checklist

- [ ] Without the materials or without Carpentry 1, the Sorter Crate recipe is greyed out. It is on the Furniture page.
- [ ] With 4 Planks, 10 Screws, 1 Small Metal Sheet, a Hammer, a Screwdriver, and Carpentry 1, build the crate. The hammer and the screwdriver are still in your inventory. The materials are gone.
- [ ] The name box shows "Sorter 1". Try an empty name. Try a 25-character name. Both stay in the box and tell you why. Then accept a normal name.
- [ ] Point at the crate. The name you typed shows. Put items in. The capacity is 50.
- [ ] Build a second crate. The box suggests "Sorter 2".
- [ ] Save, quit to the desktop, and load. Both names are still there.
- [ ] Dismantle one crate (right-click, Dismantle, with a hammer and a saw). The Small Metal Sheet comes back. Some or none of the planks and screws come back. Items that were inside are on the ground, not deleted.
- [ ] On the Sandbox page, Sorter range is there, from 20 to 30, and a new game starts at 20.
- [ ] `console.txt` has no PZSorter errors. A line that says the crate save data loaded is expected.

Rotate the crate while placing it if the build menu lets you. The letter on the lid should match the facing the menu is using. If it does not, that is an art-order bug to report, not a reason to keep testing names.
