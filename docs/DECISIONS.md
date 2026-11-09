# Decisions

Owner: wesdebas. Recorded 3 November 2026.

When this file and the project plan disagree, this file wins. The design spec still wins over the plan on anything this file does not mention.

## Already in this build (step 1)

- Mod id is `PZSorter_wd`. The plan's `PZSorter_wesdebas` is not used.
- The game build we target is the current stable Build 42, which is 42.21. `versionMin` stays `42.0` so the mod is Build 42 only, without pinning one patch.
- Sorter range is a square. Distance is Chebyshev: the larger of the east-west gap and the north-south gap, in tiles. Diagonal counts the same as straight. The sandbox option is an integer from 20 to 30, default 20. The square covers the crate's floor, one floor above, and one floor below.
- Dismantling gives back part of the planks and part of the screws, scaled by Carpentry the way vanilla furniture tables do. It always gives back the 1 Small Metal Sheet, at every skill.
- The final crate art is in, in the same files the placeholder used. Facings 2 (W) and 3 (N) show the crate's back on purpose. See `docs/art/SPRITE-SPEC.md`. Do not redraw it with `tools/build_tiles.py --placeholders`.

## Already in this build (step 2)

- Outside a safehouse, anyone can use a sorter, the same way anyone can use a vanilla container. Inside a safehouse, only members can. The check is `SafeHouse.getSafeHouse` and `playerAllowed`. If that call is missing, the action is allowed and a console line says so.
- A fridge/freezer combo is two rows, one for the fridge and one for the freezer. The row name comes from the container type plus a number, like "Fridge 1".
- Picking up the crate uses the moveable item `PZSorter.SorterCrate`. The item keeps the name, id, and links. Placing it does not open the name box again. It has to be empty, the same as a vanilla container.

## Already in this build (step 3)

- Category filters use the game's inventory display categories. The saved filter also has item ticks and exclusions, but this step does not edit those.
- A realistic sort of about 50 items takes about 10 seconds, plus a little when the loot is heavy. Instant finishes on the next tick. Moodles can stretch the realistic time, the same way they stretch other timed actions.
- The sort moves items on the server only. A multiplayer client asks for each step and does not move the item itself.

## Already in this build (step 4)

- Open question 5 was not settled. The three food groups do not overlap, and the meanings live in `FilterTree.foodGroup` so they can be changed in one place.
  - **Frozen** means the food is frozen right now. It does not mean "this kind of food can be frozen". A frozen apple is Frozen, not Perishable. A frozen can is Frozen, not Non-perishable.
  - **Perishable** means food that can rot and is not frozen right now.
  - **Non-perishable** means food that never rots, such as a sealed can or dry food, and is not frozen right now.
- A container's display name is the vanilla rename, stored on the container by `ItemContainer:getCustomName` and saved by the game with that furniture. It is not in our mod data, and it is not the name on the sorter link. The link keeps the automatic name ("Sidetable 1") and the row uses that when the custom name is blank. The Rename entry this mod adds is only for the Sorter Crate.

## For later steps (do not build these yet)

- Workshop visibility is Public. wesdebas publishes the Workshop item himself.
