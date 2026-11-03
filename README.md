# PZSorter

A Project Zomboid (Build 42) mod that adds a **Sorter Crate**: drop your loot in one box, hit **Sort**, and everything goes to the right shelf, crate, fridge, or freezer in your base.

![Sorter Crate concept art](docs/images/sorter-crate-concept.jpg)
*Concept art for the Sorter Crate.*

> Status: in design. Not playable yet.

## How it works

1. **Build a Sorter Crate.** It looks like a wooden crate with a metal drop slot on top, a yellow stripe, and a branching-arrow stencil.
   - 4 Planks, 10 Screws, 1 Small Metal Sheet
   - Carpentry 1
   - Tools: Hammer and Screwdriver (not consumed)
   - Holds only 50 capacity, so it's a sorting tool, not extra storage.
2. **Name it** when you place it, like "Main Base" or "Farm".
3. **Assign containers.** Right-click any existing storage (crates, shelves, fridges, freezers, and so on) and choose **Assign to Sorter**. Only containers you assign are used. Each one must be within the sorter's range (20 tiles by default).
4. **Set filters.** Each assigned container gets a filter tree like RimWorld's storage settings. Tick a whole category like **Food**, or expand it and pick single items, like a box that only takes screws and hammers.
5. **Sort.** Right-click the Sorter Crate and choose **Sort**. Your character moves each item to the container whose filter matches. Anything that doesn't match, or doesn't fit, stays in the Sorter Crate.

## Rules

- **A specific item beats a category.** If one box takes "Hammer" and another takes all "Tools", hammers go to the first.
- **Priority breaks ties.** Each assigned container has a priority, and the higher one wins.
- **Full containers overflow** to the next matching container. If nothing has room, the item stays in the Sorter Crate.
- **Skipped items:** equipped, favorited, and key items are never moved. Bags move as whole items and aren't emptied.
- After sorting you get a short summary, like "Sorted 38, 4 left: Freezer full."

## Sandbox options

- **Sorter range:** 20 to 30 tiles (default 20).
- **Sort speed:** realistic timed action, or instant.

## Planned extras

- "Copy from contents" sets a container's filter from what it already holds.
- Search, Allow All, and Clear All in the filter tree.
- Linked containers glow while the Sorter panel is open.
- Multiplayer support that respects safehouse permissions.

## License

MIT. Use it, change it, and share it freely. See [LICENSE](LICENSE).
