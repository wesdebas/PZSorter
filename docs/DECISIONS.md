# Decisions

Owner: wesdebas. Recorded 3 November 2026.

When this file and the project plan disagree, this file wins. The design spec still wins over the plan on anything this file does not mention.

## Already in this build (step 1)

- Mod id is `PZSorter_wd`. The plan's `PZSorter_wesdebas` is not used.
- The game build we target is the current stable Build 42, which is 42.21. `versionMin` stays `42.0` so the mod is Build 42 only, without pinning one patch.
- Sorter range is a square. Distance is Chebyshev: the larger of the east-west gap and the north-south gap, in tiles. Diagonal counts the same as straight. The sandbox option is an integer from 20 to 30, default 20. The square covers the crate's floor, one floor above, and one floor below.
- Dismantling gives back part of the planks and part of the screws, scaled by Carpentry the way vanilla furniture tables do. It always gives back the 1 Small Metal Sheet, at every skill.
- The crate sprite in this branch is a temporary placeholder. The real sheet replaces the same files. See `docs/art/SPRITE-SPEC.md`.

## For later steps (do not build these yet)

- **Frozen** means the food is frozen right now. It does not mean "this kind of food can be frozen".
- **Perishable** means anything that can rot.
- Non-perishable was not given its own sentence. Until it is, treat it as food that cannot rot and is not frozen right now, so the three food groups do not overlap.
- Outside a safehouse, anyone can use a sorter, the same way anyone can use a vanilla container.
- A fridge/freezer combo is two rows, one for the fridge and one for the freezer.
- A realistic sort of 50 items takes about 10 seconds.
- Workshop visibility is Public. wesdebas publishes the Workshop item himself.
