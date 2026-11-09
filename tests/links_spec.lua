local Links = require("PZSorter.Links")

local function spot(x, y, z, index)
    return { x = x, y = y, z = z, index = index or 0 }
end

local function sorter(id, name, x, y, z)
    return { id = id, name = name, x = x or 0, y = y or 0, z = z or 0, links = {} }
end

describe("container links", function()
    it("names the first fridge, freezer, and crate from the container type", function()
        local home = sorter("1", "Home")
        local fridge = Links.add(home, spot(1, 1, 0), "fridge", nil)
        local freezer = Links.add(home, spot(1, 1, 0, 1), "freezer", nil)
        local crate = Links.add(home, spot(2, 2, 0), "crate", nil)
        assert.are.equal("Fridge 1", fridge.name)
        assert.are.equal("Freezer 1", freezer.name)
        assert.are.equal("Crate 1", crate.name)
        assert.are.equal(5, fridge.priority)
        assert.are.same({}, fridge.filter)
        assert.are.equal(5, Links.clampPriority(nil))
        assert.are.equal(5, Links.clampPriority("nope"))
        assert.are.equal(1, Links.clampPriority(0))
        assert.are.equal(1, Links.clampPriority(1))
        assert.are.equal(8, Links.clampPriority(8.9))
        assert.are.equal(9, Links.clampPriority(9))
        assert.are.equal(9, Links.clampPriority(10))
        assert.are.equal(8, Links.clampPriority("8"))
        local second = Links.add(home, spot(3, 3, 0), "crate", nil)
        assert.are.equal("Crate 2", second.name)
    end)

    it("reuses the lowest type number after an unassign", function()
        local home = sorter("1", "Home")
        Links.add(home, spot(1, 1, 0), "fridge", nil)
        Links.add(home, spot(2, 2, 0), "fridge", nil)
        assert.is_truthy(Links.remove(home, spot(1, 1, 0)))
        local again = Links.add(home, spot(4, 4, 0), "fridge", nil)
        assert.are.equal("Fridge 1", again.name)
        assert.is_nil(Links.find(home.links, 1, 1, 0, 0))
    end)

    it("gives a container to only one sorter", function()
        local home = sorter("1", "Home")
        local farm = sorter("2", "Farm")
        local place = spot(5, 5, 0)
        assert.are.equal("Crate 1", Links.add(home, place, "crate", nil).name)
        local denied, reason = Links.add(farm, place, "crate", home.id)
        assert.is_nil(denied)
        assert.are.equal("owned", reason)
        local owner = Links.lookup({ home, farm }, place)
        assert.are.equal("1", tostring(owner.id))
        assert.is_nil(Links.find(farm.links, 5, 5, 0, 0))
    end)

    it("moves a container from one sorter to the other and does not share it", function()
        local home = sorter("1", "Home")
        local farm = sorter("2", "Farm")
        local place = spot(5, 5, 0)
        Links.add(home, place, "crate", nil)
        Links.add(farm, spot(9, 9, 0), "crate", nil)
        local moved = Links.move(home, farm, place, "crate")
        assert.are.equal("Crate 2", moved.name)
        assert.is_nil(Links.find(home.links, 5, 5, 0, 0))
        assert.is_not_nil(Links.find(farm.links, 5, 5, 0, 0))
        local owner = Links.lookup({ home, farm }, place)
        assert.are.equal("2", tostring(owner.id))
        local second = Links.lookup({ farm, home }, place)
        assert.are.equal(owner, second)
    end)

    it("unassign drops the link and a second unassign does nothing", function()
        local home = sorter("1", "Home")
        Links.add(home, spot(1, 2, 0), "counter", nil)
        local removed = Links.remove(home, spot(1, 2, 0))
        assert.are.equal("Counter 1", removed.name)
        local again, reason = Links.remove(home, spot(1, 2, 0))
        assert.is_nil(again)
        assert.are.equal("not_linked", reason)
        assert.are.equal(0, #home.links)
    end)

    it("still finds links after a save rewrites the list with string keys", function()
        local home = sorter("1", "Home")
        Links.add(home, spot(1, 1, 0), "crate", nil)
        local saved = { ["1"] = home.links[1] }
        home.links = saved
        local found = Links.find(home.links, 1, 1, 0, 0)
        assert.are.equal("Crate 1", found.name)
        local removed = Links.remove(home, spot(1, 1, 0))
        assert.are.equal("Crate 1", removed.name)
        assert.are.equal(0, #home.links)
    end)

    it("refuses sorters, the player, worn bags, vehicles, and corpses", function()
        assert.are.equal("sorter", Links.exclusion({ sorter = true, container = true }))
        assert.are.equal("player", Links.exclusion({ player = true, container = true }))
        assert.are.equal("equipped", Links.exclusion({ equippedBag = true, container = true }))
        assert.are.equal("vehicle", Links.exclusion({ vehicle = true, container = true }))
        assert.are.equal("corpse", Links.exclusion({ corpse = true, container = true }))
        assert.are.equal("not_container", Links.exclusion({ container = false }))
        assert.is_nil(Links.exclusion({ container = true }))
    end)

    it("lists an in-range sorter, greys one step past the range, and hides two floors away", function()
        local target = { x = 0, y = 0, z = 0 }
        local sorters = {
            sorter("1", "Near", 20, 0, 0),
            sorter("2", "Far", 21, 0, 0),
            sorter("3", "Upstairs", 0, 0, 1),
            sorter("4", "Attic", 0, 0, 2),
            sorter("5", "Wide", 30, 0, 0),
        }
        local entries = Links.menuEntries(sorters, target, 20, nil)
        local byId = {}
        for i = 1, #entries do
            byId[entries[i].id] = entries[i]
        end
        assert.are.equal("assign", byId["1"].action)
        assert.is_true(byId["1"].enabled)
        assert.is_false(byId["2"].enabled)
        assert.is_true(byId["3"].enabled)
        assert.is_nil(byId["4"])
        assert.is_false(byId["5"].enabled)
        local atThirty = Links.menuEntries(sorters, target, 30, nil)
        local wide = nil
        for i = 1, #atThirty do
            if atThirty[i].id == "5" then
                wide = atThirty[i]
            end
        end
        assert.is_true(wide.enabled)
    end)

    it("offers Move and Unassign when another sorter already owns the container", function()
        local target = { x = 0, y = 0, z = 0 }
        local home = sorter("1", "Home", 2, 0, 0)
        local farm = sorter("2", "Farm", 4, 0, 0)
        local entries = Links.menuEntries({ home, farm }, target, 20, "1")
        assert.are.equal("unassign", entries[1].action)
        assert.are.equal("Home", entries[1].name)
        assert.is_true(entries[1].enabled)
        assert.are.equal("move", entries[2].action)
        assert.are.equal("Farm", entries[2].name)
        assert.is_true(entries[2].enabled)
    end)

    it("marks a missing container, an out-of-range one, and one whose square is not loaded", function()
        local origin = { x = 0, y = 0, z = 0 }
        local link = { x = 20, y = 0, z = 0, index = 0 }
        assert.are.equal("ok", Links.status(origin, link, 20, true, true))
        assert.are.equal("range", Links.status(origin, { x = 21, y = 0, z = 0 }, 20, true, true))
        assert.are.equal("missing", Links.status(origin, link, 20, false, true))
        assert.are.equal("unloaded", Links.status(origin, link, 20, false, false))
        assert.are.equal("ok", Links.status(origin, { x = 0, y = 0, z = 1 }, 20, true, true))
        assert.are.equal("range", Links.status(origin, { x = 0, y = 0, z = 2 }, 20, true, true))
    end)
end)
