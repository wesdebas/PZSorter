-- What you get back when a Sorter Crate is dismantled.
--
-- Pure Lua, same as the naming and range rules, so the tests can roll the
-- dice with a stand-in instead of the game's random number generator.
--
-- Vanilla furniture does not give the whole recipe back. Each plank and each
-- screw is a separate try, and Carpentry makes each try more likely. The
-- published tables (the medicine-cabinet dismantle table on the PZwiki) list
-- a base chance of 40 for many plank rolls and 50 for screw and nail rolls.
-- A Build 42 carpentry write-up lists what a base of 50 becomes in play:
-- 5% at Carpentry 0, 10% at 1, 55% at 10. That series is
-- base * (level + 1) / 10, and it never goes past 100. We could not vendor
-- the game's own function (it ships inside the game), so this is that public
-- series applied to our recipe: 4 plank tries at base 40, 10 screw tries at
-- base 50.
--
-- The owner's decision on top of that: the 1 Small Metal Sheet always comes
-- back, at every skill, even when every plank and screw try fails. It is not
-- one of the rolls.

PZSorter = PZSorter or {}
PZSorter.Dismantle = PZSorter.Dismantle or {}

local Dismantle = PZSorter.Dismantle

-- Loaded lazily so this file still works if the game's loader runs it before
-- Config.lua. The tests set the package path and require in any order.
if not PZSorter.Config then
    require "PZSorter/Config"
end

-- Base chances copied from the public dismantle tables. See the header.
Dismantle.PLANK_BASE_CHANCE = 40
Dismantle.SCREW_BASE_CHANCE = 50

-- Percent chance for one try. `base` is the table's base chance, not a
-- percent you can read off the character sheet. Level 0 is the lowest.
function Dismantle.chancePercent(baseChance, carpentryLevel)
    local level = tonumber(carpentryLevel)
    if level == nil then
        level = 0
    end
    level = math.floor(level)
    if level < 0 then
        level = 0
    end
    local chance = baseChance * (level + 1) / 10
    if chance > 100 then
        return 100
    end
    if chance < 0 then
        return 0
    end
    return chance
end

-- roll(tryNumber) must return an integer from 1 to 100. A try succeeds when
-- the roll is less than or equal to the chance. Try 1..4 are the planks.
-- Try 5..14 are the screws. The sheet is not a try.
function Dismantle.returns(carpentryLevel, roll)
    local config = PZSorter.Config
    local plankChance = Dismantle.chancePercent(Dismantle.PLANK_BASE_CHANCE, carpentryLevel)
    local screwChance = Dismantle.chancePercent(Dismantle.SCREW_BASE_CHANCE, carpentryLevel)
    local planks = 0
    local screws = 0
    local tryNumber = 1
    for _ = 1, config.PLANKS_USED do
        if roll(tryNumber) <= plankChance then
            planks = planks + 1
        end
        tryNumber = tryNumber + 1
    end
    for _ = 1, config.SCREWS_USED do
        if roll(tryNumber) <= screwChance then
            screws = screws + 1
        end
        tryNumber = tryNumber + 1
    end
    return {
        planks = planks,
        screws = screws,
        -- Always, even when both loops added nothing.
        smallMetalSheets = config.SHEETS_USED,
    }
end

-- Vanilla disassembly of wooden furniture asks for a hammer and a saw in
-- the inventory (a hacksaw or a small saw counts as a saw). The build tools
-- are a hammer and a screwdriver, so the saw is extra and the test steps
-- say so. Tags may arrive as "hammer" or "base:hammer"; the recipe script
-- uses the base: form.
function Dismantle.hasRequiredTools(tags)
    local hammer = false
    local saw = false
    if type(tags) ~= "table" then
        return false
    end
    for _, tag in ipairs(tags) do
        if type(tag) == "string" then
            local name = string.lower(tag)
            if name == "hammer" or name == "base:hammer" then
                hammer = true
            end
            if name == "saw" or name == "base:saw"
                or name == "hacksaw" or name == "base:hacksaw"
                or name == "smallsaw" or name == "base:smallsaw" then
                saw = true
            end
        end
    end
    return hammer and saw
end

return Dismantle
