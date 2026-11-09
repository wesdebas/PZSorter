local Guard = require("PZSorter.MoveGuard")

describe("move guard", function()
    it("refuses the floor even when the ground has room", function()
        local allowed, reason = Guard.allow({
            type = "floor",
            floor = true,
            addable = true,
            sameAsSource = false,
            room = true,
        })
        assert.is_false(allowed)
        assert.are.equal("floor", reason)
        local byType = Guard.allow({ type = "floor", addable = true, room = true })
        assert.is_false(byType)
    end)

    it("refuses a container that has no room at the moment of the move", function()
        local allowed, reason = Guard.allow({
            type = "sidetable",
            addable = true,
            sameAsSource = false,
            room = false,
        })
        assert.is_false(allowed)
        assert.are.equal("full", reason)
    end)

    it("allows a real container that still has room", function()
        local allowed = Guard.allow({
            type = "sidetable",
            addable = true,
            sameAsSource = false,
            room = true,
        })
        assert.is_true(allowed)
    end)

    it("puts a failed add back in the source and never onto the ground", function()
        assert.are.equal("restore", Guard.afterRemove(false))
        assert.are.equal("restore", Guard.afterRemove(nil))
        assert.are.equal("done", Guard.afterRemove(true))
    end)
end)
