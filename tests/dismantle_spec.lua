local Dismantle = require("PZSorter.Dismantle")
local Config = require("PZSorter.Config")

local function always(value)
    return function()
        return value
    end
end

local function scripted(values)
    local index = 0
    return function()
        index = index + 1
        return values[index]
    end
end

describe("dismantle returns", function()
    it("uses the recipe counts", function()
        assert.are.equal(4, Config.PLANKS_USED)
        assert.are.equal(10, Config.SCREWS_USED)
        assert.are.equal(1, Config.SHEETS_USED)
        assert.are.equal(50, Config.CAPACITY)
    end)

    it("follows the published chance table", function()
        -- Base 50: 5% at level 0, then +5% per level, matching the public
        -- nail table. Base 40 is the plank row from the same kind of table.
        assert.are.equal(5, Dismantle.chancePercent(50, 0))
        assert.are.equal(10, Dismantle.chancePercent(50, 1))
        assert.are.equal(55, Dismantle.chancePercent(50, 10))
        assert.are.equal(4, Dismantle.chancePercent(40, 0))
        assert.are.equal(8, Dismantle.chancePercent(40, 1))
        assert.are.equal(44, Dismantle.chancePercent(40, 10))
        assert.are.equal(100, Dismantle.chancePercent(50, 30))
        assert.are.equal(5, Dismantle.chancePercent(50, -3))
        assert.are.equal(5, Dismantle.chancePercent(50, nil))
    end)

    it("always returns the one small metal sheet when every try fails", function()
        local result = Dismantle.returns(1, always(100))
        assert.are.equal(0, result.planks)
        assert.are.equal(0, result.screws)
        assert.are.equal(1, result.smallMetalSheets)
    end)

    it("always returns the sheet when every try succeeds too", function()
        local result = Dismantle.returns(0, always(1))
        assert.are.equal(4, result.planks)
        assert.are.equal(10, result.screws)
        assert.are.equal(1, result.smallMetalSheets)
    end)

    it("succeeds a try only when the roll is inside the chance", function()
        -- Level 1: planks succeed on 1..8, screws on 1..10.
        -- Four plank rolls, then ten screw rolls.
        local rolls = {
            8, 9, 1, 8,
            10, 11, 1, 10, 100, 10, 5, 10, 9, 11,
        }
        local result = Dismantle.returns(1, scripted(rolls))
        assert.are.equal(3, result.planks)
        assert.are.equal(7, result.screws)
        assert.are.equal(1, result.smallMetalSheets)
    end)

    it("asks for a hammer and a saw", function()
        assert.is_false(Dismantle.hasRequiredTools({}))
        assert.is_false(Dismantle.hasRequiredTools({ "base:hammer" }))
        assert.is_false(Dismantle.hasRequiredTools({ "base:saw" }))
        assert.is_false(Dismantle.hasRequiredTools({ "base:screwdriver" }))
        assert.is_true(Dismantle.hasRequiredTools({ "base:hammer", "base:saw" }))
        assert.is_true(Dismantle.hasRequiredTools({ "hammer", "hacksaw" }))
        assert.is_true(Dismantle.hasRequiredTools({ "BASE:HAMMER", "base:smallsaw" }))
    end)
end)
