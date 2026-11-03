local Names = require("PZSorter.Names")

describe("sorter names", function()
    it("suggests Sorter 1 when nothing is named yet", function()
        assert.are.equal("Sorter 1", Names.nextDefault({}))
        assert.are.equal("Sorter 1", Names.nextDefault(nil))
    end)

    it("suggests the next number after Sorter 1", function()
        assert.are.equal("Sorter 2", Names.nextDefault({ "Sorter 1" }))
    end)

    it("fills a gap instead of skipping ahead", function()
        assert.are.equal("Sorter 1", Names.nextDefault({ "Sorter 2" }))
        assert.are.equal("Sorter 2", Names.nextDefault({ "Sorter 1", "Sorter 3" }))
    end)

    it("ignores custom names and a different capitalisation", function()
        assert.are.equal("Sorter 1", Names.nextDefault({ "Pantry", "sorter 1" }))
        assert.are.equal("Sorter 2", Names.nextDefault({ "Sorter 1", "Main Base" }))
        -- Leading zeros are still that number, so "Sorter 01" uses up 1.
        assert.are.equal("Sorter 2", Names.nextDefault({ "Sorter 01" }))
    end)

    it("reads names out of the world records", function()
        local records = {
            a = { name = "Sorter 1" },
            b = { name = "Workshop" },
            c = { name = 12 },
        }
        assert.are.equal("Sorter 2", Names.nextFromRecords(records))
    end)

    it("trims and accepts a normal name", function()
        local name, err = Names.validate("  Main Base  ")
        assert.are.equal("Main Base", name)
        assert.is_nil(err)
    end)

    it("accepts 1 character and 24 characters", function()
        assert.are.equal("A", Names.validate("A"))
        local twentyFour = string.rep("a", 24)
        assert.are.equal(twentyFour, Names.validate(" " .. twentyFour .. " "))
    end)

    it("refuses an empty name", function()
        local name, err = Names.validate("   ")
        assert.is_nil(name)
        assert.are.equal("empty", err)
        name, err = Names.validate("")
        assert.is_nil(name)
        assert.are.equal("empty", err)
        name, err = Names.validate(nil)
        assert.is_nil(name)
        assert.are.equal("empty", err)
    end)

    it("refuses a name over 24 characters, counted after trimming", function()
        local name, err = Names.validate(string.rep("b", 25))
        assert.is_nil(name)
        assert.are.equal("too_long", err)
        name, err = Names.validate("  " .. string.rep("b", 25) .. "  ")
        assert.is_nil(name)
        assert.are.equal("too_long", err)
    end)

    it("counts utf-8 characters rather than bytes", function()
        local accented = string.char(195, 169) -- é, two bytes, one character
        assert.are.equal(string.rep(accented, 24), Names.validate(string.rep(accented, 24)))
        local name, err = Names.validate(string.rep(accented, 25))
        assert.is_nil(name)
        assert.are.equal("too_long", err)
    end)
end)
