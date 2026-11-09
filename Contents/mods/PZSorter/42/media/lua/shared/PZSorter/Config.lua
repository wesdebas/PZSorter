-- Shared constants for the Sorter Crate.
--
-- These values are also written into the tile pack and the entity script by
-- tools/build_tiles.py. They have to stay in lockstep: the game looks the
-- sprite up by name, and the capacity on the tile is what survives a reload.
-- Changing a name here without rebuilding the pack makes the crate invisible.

PZSorter = PZSorter or {}

PZSorter.Config = {
    -- Bumped only when the saved shape changes. Step 2 filled the link list
    -- step 1 reserved. Step 3 stores priority and the filter sets on that
    -- same link, so the schema stays 1.
    SCHEMA = 1,
    -- Weight capacity of the crate. Comes from the tile property too.
    CAPACITY = 50,
    -- Key used both for the object's own mod data and the world mod data.
    MOD_DATA_KEY = "PZSorter",
    -- Client commands use this module name. It matches the script module.
    COMMAND_MODULE = "PZSorter",
    -- Tileset name. Sprite names are this plus "_" plus the cell index.
    TILESET = "pzsorter_crate_01",
    -- Cell order is East, South, West, North. The entity script maps the
    -- same four letters onto these four sprites. docs/art/SPRITE-SPEC.md
    -- explains why this order was chosen and what is still uncertain.
    FACINGS = {
        E = "pzsorter_crate_01_0",
        S = "pzsorter_crate_01_1",
        W = "pzsorter_crate_01_2",
        N = "pzsorter_crate_01_3",
    },
    -- Full item types the recipe uses, and that dismantling gives back.
    ITEMS = {
        plank = "Base.Plank",
        screws = "Base.Screws",
        smallMetalSheet = "Base.SmallSheetMetal",
    },
    -- How many of each the recipe consumes. Dismantle rolls the planks and
    -- the screws. The metal sheet is not rolled: it always comes back.
    PLANKS_USED = 4,
    SCREWS_USED = 10,
    SHEETS_USED = 1,
}

-- True when this sprite name is one of the four crate facings.
-- Anything else (a vanilla crate, an empty square) is ignored on purpose,
-- so we never attach sorter data to furniture that is not ours.
function PZSorter.Config.isSorterSpriteName(spriteName)
    if type(spriteName) ~= "string" then
        return false
    end
    local facings = PZSorter.Config.FACINGS
    return spriteName == facings.E
        or spriteName == facings.S
        or spriteName == facings.W
        or spriteName == facings.N
end

-- 42.21 single player reports isClient() and isServer() both false.
-- A guard written as "if not isServer() then return" therefore skips the
-- only process that can save the name or remove the crate.
-- Dedicated server: isServer() true, isClient() false.
-- Multiplayer client: isClient() true, isServer() false.
-- Single player: both false, and this process is both the player and the save.

function PZSorter.Config.onAuthority()
    if isServer and isServer() then
        return true
    end
    if isClient and isClient() then
        return false
    end
    return true
end

function PZSorter.Config.onPlayer()
    if isClient and isClient() then
        return true
    end
    if isServer and isServer() then
        return false
    end
    return true
end

return PZSorter.Config
