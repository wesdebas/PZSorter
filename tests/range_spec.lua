local Range = require("PZSorter.Range")

local function at(x, y, z)
    return { x = x, y = y, z = z }
end

describe("sorter range", function()
    it("clamps the sandbox value to 20..30 and defaults to 20", function()
        assert.are.equal(20, Range.MIN)
        assert.are.equal(30, Range.MAX)
        assert.are.equal(20, Range.DEFAULT)
        assert.are.equal(1, Range.FLOOR_SPAN)
        assert.are.equal(20, Range.clamp(nil))
        assert.are.equal(20, Range.clamp("nope"))
        assert.are.equal(20, Range.clamp(19))
        assert.are.equal(20, Range.clamp(0))
        assert.are.equal(25, Range.clamp(25))
        assert.are.equal(25, Range.clamp("25"))
        assert.are.equal(30, Range.clamp(30))
        assert.are.equal(30, Range.clamp(31))
        assert.are.equal(20, Range.clamp(20.9))
    end)

    local crate = at(10, 20, 0)

    it("includes the crate's own square and a tile exactly 20 away", function()
        assert.is_true(Range.isInRange(crate, at(10, 20, 0), 20))
        assert.is_true(Range.isInRange(crate, at(30, 20, 0), 20))
        assert.is_true(Range.isInRange(crate, at(-10, 20, 0), 20))
    end)

    it("excludes the tile one step past the range", function()
        assert.is_false(Range.isInRange(crate, at(31, 20, 0), 20))
        assert.is_false(Range.isInRange(crate, at(10, 41, 0), 20))
    end)

    it("counts a diagonal as a square, not as a circle", function()
        -- 20 east and 20 south is 20 steps of Chebyshev, and about 28 of
        -- straight-line distance. The square includes it. A circle of 20 would not.
        assert.is_true(Range.isInRange(crate, at(30, 40, 0), 20))
        assert.is_false(Range.isInRange(crate, at(30, 41, 0), 20))
    end)

    it("reaches one floor up and one floor down, and not two", function()
        assert.is_true(Range.isInRange(crate, at(10, 20, 1), 20))
        assert.is_true(Range.isInRange(crate, at(10, 20, -1), 20))
        assert.is_false(Range.isInRange(crate, at(10, 20, 2), 20))
        assert.is_false(Range.isInRange(crate, at(10, 20, -2), 20))
        -- Height does not buy extra horizontal reach.
        assert.is_false(Range.isInRange(crate, at(31, 20, 1), 20))
    end)

    it("uses the sandbox value, including the top of the option", function()
        assert.is_true(Range.isInRange(crate, at(40, 20, 0), 30))
        assert.is_false(Range.isInRange(crate, at(41, 20, 0), 30))
        -- 31 is not a legal option. It clamps to 30, so 31 tiles is still out.
        assert.is_false(Range.isInRange(crate, at(41, 20, 0), 31))
        -- A missing option is the default of 20.
        assert.is_true(Range.isInRange(crate, at(30, 20, 0), nil))
        assert.is_false(Range.isInRange(crate, at(31, 20, 0), nil))
    end)

    it("reads a missing sandbox option as 20", function()
        assert.are.equal(20, Range.current())
    end)

    it("rejects a point that is not a tile coordinate", function()
        assert.is_false(Range.isInRange(crate, { x = 10, y = 20 }, 20))
        assert.is_false(Range.isInRange(nil, crate, 20))
    end)
end)
