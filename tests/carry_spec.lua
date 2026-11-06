local Carry = require("PZSorter.Carry")

local function record()
    return {
        schema = 1,
        id = "4",
        name = "Home",
        nameConfirmed = true,
        appliedName = "Home",
        x = 1,
        y = 2,
        z = 0,
        links = {
            {
                x = 5, y = 5, z = 0, index = 0,
                name = "Fridge 1",
                priority = 7,
                filter = { food = true },
            },
            {
                x = 8, y = 1, z = 1, index = 1,
                name = "Crate 2",
                priority = 5,
                filter = {},
            },
        },
    }
end

describe("picked up sorter crate", function()
    it("names an inventory item with setName(string) and setCustomName(true)", function()
        -- InventoryItem:setCustomName is boolean-only in 42.21. A string
        -- argument is the error screen from pickup.
        local names = {}
        local flags = {}
        local item = {
            setName = function(self, value)
                assert.are.equal("string", type(value))
                names[#names + 1] = value
            end,
            setCustomName = function(self, value)
                assert.are.equal("boolean", type(value))
                flags[#flags + 1] = value
            end,
        }
        assert.is_true(Carry.nameItem(item, "Home"))
        assert.are.same({ "Home" }, names)
        assert.are.same({ true }, flags)
        assert.is_false(Carry.nameItem(item, ""))
        assert.is_false(Carry.nameItem(nil, "Home"))
    end)

    it("builds the other facing the way getFaces does, spriteID plus offset", function()
        local sheet = "pzsorter_crate_01_"
        -- East cell is index 0. North is 3, west is 2, south is 1.
        assert.are.equal("pzsorter_crate_01_3", Carry.offsetSprite(sheet, 0, 3))
        assert.are.equal("pzsorter_crate_01_2", Carry.offsetSprite(sheet, 0, 2))
        assert.are.equal("pzsorter_crate_01_1", Carry.offsetSprite(sheet, 0, 1))
        -- North cell is index 3. East is 3 + -3.
        assert.are.equal("pzsorter_crate_01_0", Carry.offsetSprite(sheet, 3, -3))
        assert.are.equal("pzsorter_crate_01_1", Carry.offsetSprite(sheet, 3, -2))
        assert.are.equal("pzsorter_crate_01_2", Carry.offsetSprite(sheet, 3, -1))
    end)

    it("refuses pickup when the crate still holds items", function()
        assert.is_true(Carry.canPickUp(0))
        assert.is_false(Carry.canPickUp(1))
        assert.is_false(Carry.canPickUp(4))
        assert.is_false(Carry.canPickUp(nil))
    end)

    it("keeps the name, id, links, priority and filter from crate to item to crate", function()
        local source = record()
        local packed = Carry.pack(source)
        assert.are.equal("4", packed.id)
        assert.are.equal("Home", packed.name)
        assert.is_true(packed.nameConfirmed)
        assert.are.equal(2, #packed.links)
        -- The item's copy is not the crate's table. Changing one must not
        -- change the other before the crate is placed again.
        packed.links[1].filter.food = false
        packed.links[1].name = "Changed"
        assert.is_true(source.links[1].filter.food)
        assert.are.equal("Fridge 1", source.links[1].name)

        local placed = Carry.restore(packed, 30, 4, 1)
        assert.are.equal("4", placed.id)
        assert.are.equal("Home", placed.name)
        assert.is_true(placed.nameConfirmed)
        assert.are.equal("Home", placed.appliedName)
        assert.are.equal(30, placed.x)
        assert.are.equal(4, placed.y)
        assert.are.equal(1, placed.z)
        assert.are.equal(2, #placed.links)
        assert.are.equal("Changed", placed.links[1].name)
        assert.are.equal(7, placed.links[1].priority)
        assert.is_false(placed.links[1].filter.food)
        assert.are.equal(0, placed.links[1].index)
        assert.are.equal("Crate 2", placed.links[2].name)
        assert.are.equal(1, placed.links[2].index)
        assert.are.equal(1, placed.links[2].z)
        -- A later edit of the placed crate must not rewrite the item.
        placed.links[2].priority = 1
        assert.are.equal(5, packed.links[2].priority)
    end)

    it("still round-trips when a save stored the links under string keys", function()
        local saved = record()
        saved.links = { ["1"] = saved.links[1], ["2"] = saved.links[2] }
        local placed = Carry.restore(Carry.pack(saved), 2, 2, 0)
        assert.are.equal(2, #placed.links)
        assert.are.equal("4", placed.id)
        assert.are.equal("Home", placed.name)
    end)

    it("drops one link from the carried copy and leaves the other", function()
        local packed = Carry.pack(record())
        local removed = Carry.dropLink(packed, { x = 5, y = 5, z = 0, index = 0 })
        assert.are.equal("Fridge 1", removed.name)
        assert.are.equal(1, #packed.links)
        assert.are.equal("Crate 2", packed.links[1].name)
        local placed = Carry.restore(packed, 3, 3, 0)
        assert.are.equal(1, #placed.links)
        assert.are.equal("Crate 2", placed.links[1].name)
    end)

    it("marks the world row carried so another sorter is not offered that crate", function()
        local packed = Carry.pack(record())
        local entry = Carry.asCarried({ x = 1, y = 2, z = 0, name = "Home" }, packed)
        assert.is_true(entry.carried)
        assert.are.equal("Home", entry.name)
        assert.are.equal("4", entry.id)
        assert.are.equal(1, entry.x)
        assert.are.equal(2, #entry.links)
        local entries = require("PZSorter.Links").menuEntries(
            { entry, { id = "9", name = "Farm", x = 4, y = 2, z = 0 } },
            { x = 5, y = 5, z = 0 },
            20,
            "4"
        )
        assert.are.equal("unassign", entries[1].action)
        assert.are.equal("Home", entries[1].name)
        assert.are.equal("move", entries[2].action)
        assert.are.equal("Farm", entries[2].name)
        assert.is_nil(entries[3])
    end)
end)
