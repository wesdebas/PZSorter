local Plan = require("PZSorter.SortPlan")

local function item(id, category, extra)
    local row = {
        id = id,
        category = category,
        type = "Base." .. tostring(id),
        weight = 1,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            row[key] = value
        end
    end
    return row
end

local function container(id, name, category, priority, x, extra)
    local row = {
        id = id,
        name = name,
        x = x or 1,
        y = 0,
        z = 0,
        priority = priority,
        filter = { categories = {} },
        weight = 0,
        capacity = 50,
        inRange = true,
        missing = false,
    }
    if category then
        row.filter.categories[category] = true
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            row[key] = value
        end
    end
    return row
end

local function build(items, containers)
    return Plan.build({
        sorter = { x = 0, y = 0, z = 0 },
        items = items,
        containers = containers,
    })
end

local function destinations(result)
    local map = {}
    for i = 1, #result.moves do
        map[result.moves[i].itemId] = result.moves[i].containerName
    end
    return map
end

local function leftoverReason(result, id)
    for i = 1, #result.leftovers do
        if result.leftovers[i].itemId == id then
            return result.leftovers[i].reason, result.leftovers[i].containerName
        end
    end
    return nil, nil
end

describe("sort rules", function()
    it("skips equipped, favorited, and key items, and still moves a normal one", function()
        local fridge = container("fridge", "Fridge 1", "Food", 5, 1)
        local result = build({
            item("sword", "Weapon", { equipped = true }),
            item("teddy", "Junk", { favorited = true, category = "Food" }),
            item("housekey", "Junk", { key = true, category = "Food" }),
            item("apple", "Food"),
        }, { fridge })
        assert.are.same({ apple = "Fridge 1" }, destinations(result))
        assert.are.equal("equipped", leftoverReason(result, "sword"))
        assert.are.equal("favorited", leftoverReason(result, "teddy"))
        assert.are.equal("key", leftoverReason(result, "housekey"))
        assert.are.equal(1, #result.moves)
    end)

    it("reports one reason when a skipped item matches more than one skip", function()
        local fridge = container("fridge", "Fridge 1", "Food", 5, 1)
        local result = build({
            item("key", "Food", { equipped = true, key = true, favorited = true }),
        }, { fridge })
        assert.are.equal(0, #result.moves)
        assert.are.equal("equipped", leftoverReason(result, "key"))
    end)

    it("moves a bag as one item and does not sort what is inside it", function()
        local bags = container("bags", "Crate 1", "Bag", 5, 1)
        local fridge = container("fridge", "Fridge 1", "Food", 5, 2)
        local result = build({
            item("duffel", "Bag", {
                bag = true,
                weight = 8,
                contents = {
                    item("hidden-apple", "Food"),
                    item("hidden-soup", "Food"),
                },
            }),
        }, { bags, fridge })
        assert.are.equal(1, #result.moves)
        assert.are.equal("Crate 1", destinations(result).duffel)
        assert.is_nil(destinations(result)["hidden-apple"])
        assert.is_nil(leftoverReason(result, "hidden-apple"))
        assert.is_nil(leftoverReason(result, "hidden-soup"))
    end)

    it("gives nothing to a container whose filter is empty", function()
        local bare = container("bare", "Crate 1", nil, 9, 1, { filter = {} })
        local result = build({ item("apple", "Food"), item("hammer", "Tools") }, { bare })
        assert.are.equal(0, #result.moves)
        assert.are.equal("no_match", leftoverReason(result, "apple"))
        assert.are.equal("no_match", leftoverReason(result, "hammer"))
        assert.is_nil(select(2, leftoverReason(result, "apple")))
    end)

    it("sends a category only to containers that tick that category", function()
        local fridge = container("fridge", "Fridge 1", "Food", 5, 1)
        local tools = container("tools", "Crate A", "Tools", 5, 2)
        local result = build({
            item("apple", "Food"),
            item("hammer", "Tools"),
            item("shirt", "Clothing"),
        }, { fridge, tools })
        local where = destinations(result)
        assert.are.equal("Fridge 1", where.apple)
        assert.are.equal("Crate A", where.hammer)
        assert.are.equal("no_match", leftoverReason(result, "shirt"))
    end)

    it("rejects an unticked type under a ticked category", function()
        local fridge = container("fridge", "Fridge 1", "Food", 5, 1, {
            filter = {
                categories = { Food = true },
                excluded = { ["Base.beans"] = true },
            },
        })
        local result = build({
            item("apple", "Food"),
            item("beans", "Food"),
        }, { fridge })
        assert.are.equal("Fridge 1", destinations(result).apple)
        assert.are.equal("no_match", leftoverReason(result, "beans"))
    end)

    it("sends a hammer ticked on its own to that box and other tools to the category", function()
        -- The inventory calls this category Tool. Box A ticks only the
        -- hammer. Box B ticks the whole category and has the higher priority.
        local boxA = container("a", "Box A", nil, 1, 8, {
            filter = { items = { ["Base.hammer"] = true } },
        })
        local boxB = container("b", "Box B", "Tool", 9, 1)
        local result = build({
            item("hammer", "Tool"),
            item("saw", "Tool"),
        }, { boxB, boxA })
        assert.are.equal("Box A", destinations(result).hammer)
        assert.are.equal("Box B", destinations(result).saw)
        assert.are.equal("Box A", result.moves[1].ranked[1].name)
    end)

    it("breaks an item-tick tie by priority, then overflows to the next item tick", function()
        local low = container("low", "Box A", nil, 4, 1, {
            filter = { items = { ["Base.hammer"] = true } },
            maxItems = 1,
            capacity = 100,
        })
        local high = container("high", "Box B", nil, 8, 4, {
            filter = { items = { ["Base.hammer"] = true } },
            maxItems = 1,
            capacity = 100,
        })
        local result = build({
            item("hammer", "Tool"),
            item("spare", "Tool", { type = "Base.hammer" }),
        }, { low, high })
        assert.are.equal("Box B", destinations(result).hammer)
        assert.are.equal("Box A", destinations(result).spare)
        local packed = build({
            item("hammer", "Tool"),
            item("spare", "Tool", { type = "Base.hammer" }),
            item("third", "Tool", { type = "Base.hammer" }),
        }, { low, high })
        assert.are.equal("full", leftoverReason(packed, "third"))
        assert.are.equal("Box B", select(2, leftoverReason(packed, "third")))
    end)

    it("sorts perishable, frozen, and non-perishable food apart", function()
        local fridge = container("fridge", "Fridge 1", nil, 5, 1, {
            filter = { categories = { ["Food.Perishable"] = true } },
        })
        local shelf = container("shelf", "Shelf 1", nil, 5, 2, {
            filter = { categories = { ["Food.NonPerishable"] = true } },
        })
        local freezer = container("freezer", "Freezer 1", nil, 5, 3, {
            filter = { categories = { ["Food.Frozen"] = true } },
        })
        local result = build({
            item("apple", "Food", { food = true, canRot = true, frozen = false }),
            item("beans", "Food", { food = true, canRot = false, frozen = false }),
            item("frozenapple", "Food", { food = true, canRot = true, frozen = true }),
        }, { fridge, shelf, freezer })
        assert.are.equal("Fridge 1", destinations(result).apple)
        assert.are.equal("Shelf 1", destinations(result).beans)
        assert.are.equal("Freezer 1", destinations(result).frozenapple)
    end)

    it("rejects canned food from a perishable-only fridge", function()
        local fridge = container("fridge", "Fridge 1", nil, 5, 1, {
            filter = { categories = { ["Food.Perishable"] = true } },
        })
        local result = build({
            item("apple", "Food", { food = true, canRot = true }),
            item("beans", "Food", { food = true, canRot = false }),
        }, { fridge })
        assert.are.equal("Fridge 1", destinations(result).apple)
        assert.are.equal("no_match", leftoverReason(result, "beans"))
    end)

    it("keeps a category-only food filter accepting every food state", function()
        local fridge = container("fridge", "Fridge 1", "Food", 5, 1)
        local result = build({
            item("apple", "Food", { food = true, canRot = true }),
            item("beans", "Food", { food = true, canRot = false }),
            item("frozenapple", "Food", { food = true, canRot = true, frozen = true }),
        }, { fridge })
        assert.are.equal("Fridge 1", destinations(result).apple)
        assert.are.equal("Fridge 1", destinations(result).beans)
        assert.are.equal("Fridge 1", destinations(result).frozenapple)
    end)

    it("lets a type ticked on its own beat a higher-priority whole category", function()
        local specific = container("specific", "Box A", nil, 1, 8, {
            filter = { items = { ["Base.hammer"] = true } },
        })
        local general = container("general", "Box B", "Tools", 9, 1)
        local result = build({ item("hammer", "Tools") }, { general, specific })
        assert.are.equal("Box A", destinations(result).hammer)
        assert.are.equal("Box A", result.moves[1].ranked[1].name)
        assert.are.equal("Box B", result.moves[1].ranked[2].name)
    end)

    it("does not treat a type tick as more specific when that category is also ticked", function()
        local both = container("both", "Box A", nil, 1, 1, {
            filter = {
                categories = { Tools = true },
                items = { ["Base.hammer"] = true },
            },
        })
        local general = container("general", "Box B", "Tools", 9, 4)
        local result = build({ item("hammer", "Tools") }, { both, general })
        assert.are.equal("Box B", destinations(result).hammer)
    end)

    it("breaks a specificity tie by higher priority", function()
        local low = container("low", "Crate A", "Tools", 5, 1)
        local high = container("high", "Crate B", "Tools", 8, 9)
        local result = build({ item("hammer", "Tools"), item("saw", "Tools") }, { low, high })
        assert.are.equal("Crate B", destinations(result).hammer)
        assert.are.equal("Crate B", destinations(result).saw)
    end)

    it("breaks a priority tie by the closer container, counting a diagonal as a square", function()
        -- Chebyshev: (5, 0) is 5. (3, 4) is 4, even though the straight line is 5.
        local far = container("far", "Far Crate", "Tools", 5, 5)
        local corner = container("corner", "Near Crate", "Tools", 5, 3, { y = 4 })
        local result = build({ item("hammer", "Tools") }, { far, corner })
        assert.are.equal("Near Crate", destinations(result).hammer)
    end)

    it("uses the floor gap only after the tile distance ties", function()
        local upstairs = container("up", "Upstairs", "Tools", 5, 2, { z = 1 })
        local here = container("here", "Here", "Tools", 5, 2, { z = 0 })
        local result = build({ item("hammer", "Tools") }, { upstairs, here })
        assert.are.equal("Here", destinations(result).hammer)
        local farther = container("far", "Far", "Food", 5, 4, { z = 0 })
        local above = container("above", "Above", "Food", 5, 1, { z = 1 })
        local food = build({ item("apple", "Food") }, { farther, above })
        assert.are.equal("Above", destinations(food).apple)
    end)

    it("treats a missing priority as 5", function()
        local implied = container("implied", "Implied", "Tools", nil, 3)
        local lower = container("lower", "Lower", "Tools", 4, 1)
        local higher = container("higher", "Higher", "Tools", 6, 2)
        local againstLower = build({ item("hammer", "Tools") }, { lower, implied })
        assert.are.equal("Implied", destinations(againstLower).hammer)
        local againstHigher = build({ item("saw", "Tools") }, { implied, higher })
        assert.are.equal("Higher", destinations(againstHigher).saw)
    end)

    it("overflows on weight to the next match and names the best container when every match is full", function()
        local first = container("first", "Crate B", "Tools", 8, 2, { weight = 3, capacity = 5 })
        local second = container("second", "Crate A", "Tools", 5, 3, { weight = 0, capacity = 5 })
        local result = build({
            item("hammer", "Tools", { weight = 2 }),
            item("saw", "Tools", { weight = 2 }),
        }, { second, first })
        assert.are.equal("Crate B", destinations(result).hammer)
        assert.are.equal("Crate A", destinations(result).saw)
        local packed = container("packed", "Freezer 1", "Food", 8, 1, { weight = 5, capacity = 5 })
        local also = container("also", "Shelf 1", "Food", 4, 2, { weight = 5, capacity = 5 })
        local full = build({ item("apple", "Food", { weight = 1 }) }, { also, packed })
        assert.are.equal(0, #full.moves)
        local reason, name = leftoverReason(full, "apple")
        assert.are.equal("full", reason)
        assert.are.equal("Freezer 1", name)
    end)

    it("overflows on an item-count cap the same way it overflows on weight", function()
        local first = container("first", "Crate B", "Tools", 8, 1, { maxItems = 1, itemCount = 0, capacity = 100 })
        local second = container("second", "Crate A", "Tools", 5, 2, { maxItems = 1, itemCount = 0, capacity = 100 })
        local result = build({
            item("hammer", "Tools"),
            item("saw", "Tools"),
        }, { first, second })
        assert.are.equal("Crate B", destinations(result).hammer)
        assert.are.equal("Crate A", destinations(result).saw)
        local third = build({
            item("hammer", "Tools"),
            item("saw", "Tools"),
            item("nails", "Tools"),
        }, {
            container("only", "Crate B", "Tools", 8, 1, { maxItems = 1, capacity = 100 }),
        })
        assert.are.equal("full", leftoverReason(third, "nails"))
        assert.are.equal("Crate B", select(2, leftoverReason(third, "nails")))
    end)

    it("does not put an item on the floor, even when that is the only match with room", function()
        local ground = container("ground", "Floor", "Tools", 9, 1, { type = "floor", floor = true, capacity = 100 })
        local sidetable = container("side", "Sidetable 1", "Tools", 5, 2, { capacity = 10, weight = 9 })
        local onlyFloor = build({ item("hammer", "Tools", { weight = 1 }) }, { ground })
        assert.are.equal(0, #onlyFloor.moves)
        assert.are.equal("no_match", leftoverReason(onlyFloor, "hammer"))
        local overflow = build({ item("hammer", "Tools", { weight = 2 }) }, { ground, sidetable })
        assert.is_nil(destinations(overflow).hammer)
        assert.are.equal("full", leftoverReason(overflow, "hammer"))
        assert.are.equal("Sidetable 1", select(2, leftoverReason(overflow, "hammer")))
    end)

    it("does not use a container that is missing or out of range", function()
        local best = container("best", "Crate B", "Tools", 9, 1, { inRange = false })
        local gone = container("gone", "Crate C", "Tools", 8, 1, { missing = true })
        local ok = container("ok", "Crate A", "Tools", 5, 4)
        local result = build({ item("hammer", "Tools") }, { best, gone, ok })
        assert.are.equal("Crate A", destinations(result).hammer)
        local nowhere = build({ item("saw", "Tools") }, { best, gone })
        assert.are.equal("no_match", leftoverReason(nowhere, "saw"))
    end)

    it("sorts a mixed crate the way the category step describes", function()
        -- Fridge = Food (5), Crate A = Tools (5), Crate B = Tools (8).
        -- Crate B has room for one tool and then overflows to Crate A.
        local fridge = container("fridge", "Fridge 1", "Food", 5, 2)
        local crateA = container("a", "Crate A", "Tools", 5, 4, { capacity = 20, weight = 0 })
        local crateB = container("b", "Crate B", "Tools", 8, 6, { capacity = 5, weight = 3 })
        local result = build({
            item("apple", "Food", { weight = 1 }),
            item("hammer", "Tools", { weight = 2 }),
            item("saw", "Tools", { weight = 2 }),
            item("shirt", "Clothing", { weight = 1 }),
            item("sword", "Weapon", { equipped = true, weight = 2 }),
            item("charm", "Food", { favorited = true, weight = 0.1 }),
            item("key", "Junk", { key = true, weight = 0.1 }),
            item("duffel", "Bag", { bag = true, weight = 4, contents = { item("hidden", "Food") } }),
        }, { fridge, crateA, crateB, container("bags", "Bag Shelf", "Bag", 5, 3) })
        local where = destinations(result)
        assert.are.equal("Fridge 1", where.apple)
        assert.are.equal("Crate B", where.hammer)
        assert.are.equal("Crate A", where.saw)
        assert.are.equal("Bag Shelf", where.duffel)
        assert.are.equal("no_match", leftoverReason(result, "shirt"))
        assert.are.equal("equipped", leftoverReason(result, "sword"))
        assert.are.equal("favorited", leftoverReason(result, "charm"))
        assert.are.equal("key", leftoverReason(result, "key"))
        assert.is_nil(where.hidden)
    end)

    it("does not change the container tables it was given", function()
        local crate = container("crate", "Crate A", "Tools", 5, 1, { weight = 1, capacity = 10, itemCount = 4 })
        build({ item("hammer", "Tools", { weight = 3 }) }, { crate })
        assert.are.equal(1, crate.weight)
        assert.are.equal(4, crate.itemCount)
    end)

    it("orders equal containers by name so the choice does not depend on input order", function()
        local bravo = container("b", "Bravo", "Tools", 5, 2)
        local alpha = container("a", "Alpha", "Tools", 5, 2)
        local result = build({ item("hammer", "Tools") }, { bravo, alpha })
        assert.are.equal("Alpha", destinations(result).hammer)
        assert.are.equal("Alpha", result.moves[1].ranked[1].name)
        assert.are.equal("Bravo", result.moves[1].ranked[2].name)
    end)

    it("builds the spec's summary sentence", function()
        local moves = {}
        for i = 1, 38 do
            moves[i] = { itemId = i }
        end
        local text = Plan.summary({
            moves = moves,
            leftovers = {
                { reason = "full", containerName = "Freezer 1" },
                { reason = "full", containerName = "Freezer 1" },
                { reason = "full", containerName = "Freezer 1" },
                { reason = "no_match" },
            },
        })
        assert.are.equal("Sorted 38 items. 4 left: Freezer 1 full (3), no match (1).", text)
    end)

    it("uses the singular for one item and stops after the first sentence when nothing is left", function()
        assert.are.equal("Sorted 0 items.", Plan.summary(nil))
        assert.are.equal("Sorted 1 item.", Plan.summary({ moves = { { itemId = "a" } }, leftovers = {} }))
        assert.are.equal(
            "Sorted 1 item. 1 left: no match (1).",
            Plan.summary({ moves = { { itemId = "a" } }, leftovers = { { reason = "no_match" } } })
        )
        assert.are.equal(
            "Sorted 0 items. 3 left: Crate A full (2), Freezer 1 full (1).",
            Plan.summary({
                moves = {},
                leftovers = {
                    { reason = "full", containerName = "Crate A" },
                    { reason = "full", containerName = "Freezer 1" },
                    { reason = "full", containerName = "Crate A" },
                },
            })
        )
        assert.are.equal(
            "Sorted 0 items. 2 left: equipped (1), key (1).",
            Plan.summary({
                moves = {},
                leftovers = {
                    { reason = "equipped" },
                    { reason = "key" },
                },
            })
        )
    end)

    it("makes fifty light items about ten seconds, and instant finish on the next tick", function()
        assert.are.equal(1000, Plan.duration(50, 0, "realistic"))
        assert.are.equal(1000, Plan.duration(50, 0, nil))
        assert.are.equal(1000, Plan.duration(50, 0, 1))
        assert.are.equal(1050, Plan.duration(50, 25, "realistic"))
        assert.is_true(Plan.duration(50, 25, nil) > Plan.duration(50, 0, nil))
        assert.are.equal(1, Plan.duration(50, 100, "instant"))
        assert.are.equal(1, Plan.duration(50, 100, 2))
        assert.are.equal(1, Plan.duration(0, 40, "realistic"))
        assert.are.equal("realistic", Plan.normalizeSpeed(nil))
        assert.are.equal("realistic", Plan.normalizeSpeed(1))
        assert.are.equal("instant", Plan.normalizeSpeed(2))
        assert.are.equal("instant", Plan.normalizeSpeed("instant"))
    end)
end)
