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

    it("opens a placement prompt only while the name is still unconfirmed", function()
        local fresh = Names.promptFor({ id = "1", name = "Sorter 2", nameConfirmed = false, x = 3, y = 4, z = 0 }, false)
        assert.are.equal("Sorter 2", fresh.name)
        assert.are.equal("1", fresh.id)
        assert.is_nil(Names.promptFor({ id = "1", name = "Pantry", nameConfirmed = true }, false))
        local again = Names.promptFor({ id = "1", name = "Pantry", nameConfirmed = true }, true)
        assert.are.equal("Pantry", again.name)
        local fallback = Names.promptFor({ id = "9", nameConfirmed = false }, false)
        assert.are.equal("Sorter 1", fallback.name)
        assert.is_nil(Names.promptFor(nil, false))
    end)

    it("keeps a name the player typed instead of the automatic name still on the container", function()
        -- The container still says "Sorter 2" because that is the suggestion
        -- we wrote. The player then stored "Sorter 2sss". That typed name wins.
        local title, adopt = Names.reconcile("Sorter 2sss", "Sorter 2", "Sorter 2")
        assert.are.equal("Sorter 2sss", title)
        assert.is_false(adopt)
        title, adopt = Names.reconcile("Rename 3", "Sorter 3", "Sorter 3")
        assert.are.equal("Rename 3", title)
        assert.is_false(adopt)
        -- A loot-window rename differs from both the stored name and the
        -- name we last wrote, so it is kept and copied into the save.
        title, adopt = Names.reconcile("Sorter 2sss", "Pantry", "Sorter 2sss")
        assert.are.equal("Pantry", title)
        assert.is_true(adopt)
        title, adopt = Names.reconcile("Sorter 2sss", "Pantry", "Sorter 2")
        assert.are.equal("Pantry", title)
        assert.is_true(adopt)
    end)

    it("does not suggest a Sorter number that an existing crate still uses", function()
        assert.are.equal("Sorter 1", Names.nextFromRecords({
            a = { id = "2", name = "Sorter 2" },
        }))
        assert.are.equal("Sorter 3", Names.nextFromRecords({
            a = { id = "1", name = "Sorter 1" },
            b = { id = "2", name = "Sorter 2" },
        }))
        -- Dismantled crates free their number. A leftover name on a gone
        -- record must not keep that number reserved.
        assert.are.equal("Sorter 1", Names.nextFromRecords({
            a = { id = "1", name = "Sorter 1", gone = true },
            b = { id = "2", name = "Sorter 2" },
        }))
    end)

    it("suggests the same next name after the same crates are loaded again", function()
        local saved = {}
        Names.absorb(saved, { id = "1", name = "Sorter 1", nameConfirmed = true, x = 1, y = 2, z = 0 })
        Names.absorb(saved, { id = "2", name = "Sorter 2", nameConfirmed = true })
        Names.absorb(saved, { id = "3", name = "Sorter 3", nameConfirmed = true })
        assert.are.equal("Sorter 4", Names.nextFromRecords(saved))
        -- A reload hands the saved list back. Playing it into a fresh table
        -- is that load. The next suggestion must not start over at Sorter 1.
        local loaded = {}
        for _, record in pairs(saved) do
            Names.absorb(loaded, record)
        end
        assert.are.equal("Sorter 4", Names.nextFromRecords(loaded))
        -- Renaming the first crate off "Sorter 1" frees that number.
        Names.absorb(loaded, { id = "1", name = "Pantry", nameConfirmed = true })
        assert.are.equal("Sorter 1", Names.nextFromRecords(loaded))
        -- Dismantling frees its number too, and the id is not reused as a name.
        Names.absorb(loaded, { id = "2", gone = true })
        assert.are.equal("Sorter 1", Names.nextFromRecords(loaded))
        -- Using that free number reserves it again. Sorter 3 is still placed.
        Names.absorb(loaded, { id = "4", name = "Sorter 1", nameConfirmed = true })
        assert.are.equal("Sorter 2", Names.nextFromRecords(loaded))
    end)

    it("keeps a vanilla loot-window rename instead of writing Sorter Crate back", function()
        local title, adopt = Names.reconcile(nil, "Pantry")
        assert.are.equal("Pantry", title)
        assert.is_true(adopt)
        title, adopt = Names.reconcile("Sorter 1", "Pantry")
        assert.are.equal("Pantry", title)
        assert.is_true(adopt)
        title, adopt = Names.reconcile("Sorter 1", "Sorter 1")
        assert.are.equal("Sorter 1", title)
        assert.is_false(adopt)
        title, adopt = Names.reconcile("Sorter 1", "Sorter Crate")
        assert.are.equal("Sorter 1", title)
        assert.is_false(adopt)
        title, adopt = Names.reconcile(nil, nil)
        assert.are.equal("Sorter Crate", title)
        assert.is_false(adopt)
    end)

    it("uses the custom name in the loot window and falls back to Sorter Crate", function()
        assert.are.equal("Sorter 1", Names.containerTitle("  Sorter 1  "))
        assert.are.equal("Sorter Crate", Names.containerTitle(nil))
        assert.are.equal("Sorter Crate", Names.containerTitle("   "))
        assert.are.equal("Sorter Crate", Names.containerTitle(string.rep("a", 25)))
    end)

    it("counts utf-8 characters rather than bytes", function()
        local accented = string.char(195, 169) -- é, two bytes, one character
        assert.are.equal(string.rep(accented, 24), Names.validate(string.rep(accented, 24)))
        local name, err = Names.validate(string.rep(accented, 25))
        assert.is_nil(name)
        assert.are.equal("too_long", err)
    end)
end)
