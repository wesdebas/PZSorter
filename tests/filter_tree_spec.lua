local Tree = require("PZSorter.FilterTree")
local Filter = require("PZSorter.Filter")

local function script(fullType, category, label, extra)
    local row = {
        fullType = fullType,
        category = category,
        label = label,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            row[key] = value
        end
    end
    return row
end

local function toolTree()
    return Tree.build({
        script("Base.Hammer", "Tool", "Hammer"),
        script("Base.Screws", "Tool", "Screws"),
        script("Base.Saw", "Tool", "Saw"),
        script("OtherMod.Widget", "Widget", "Widget"),
    })
end

local function foodScripts(count, canRot)
    local scripts = {}
    for i = 1, count do
        scripts[i] = script("Base.Food" .. tostring(i), "Food", "Food " .. tostring(i), { canRot = canRot })
    end
    return scripts
end

local function labelsOf(rows)
    local labels = {}
    for i = 1, #rows do
        labels[i] = rows[i].label
    end
    return labels
end

describe("food groups", function()
    it("uses the documented meanings and does not overlap", function()
        assert.are.equal("perishable", Tree.foodGroup({ food = true, canRot = true, frozen = false }))
        assert.are.equal("frozen", Tree.foodGroup({ food = true, canRot = true, frozen = true }))
        assert.are.equal("frozen", Tree.foodGroup({ food = true, canRot = false, frozen = true }))
        assert.are.equal("nonperishable", Tree.foodGroup({ food = true, canRot = false, frozen = false }))
        assert.is_nil(Tree.foodGroup({ food = false, canRot = true, frozen = true }))
        assert.is_nil(Tree.foodGroup(nil))
        assert.is_nil(Tree.foodGroup({ frozen = true }))
    end)

    it("reads a rot lifetime, and treats a sealed can as never rotting", function()
        assert.is_true(Tree.canRot({ daysTotallyRotten = 8 }))
        assert.is_true(Tree.canRot({ offAgeMax = 4, packaged = true }))
        assert.is_false(Tree.canRot({ daysTotallyRotten = 1000000000 }))
        assert.is_false(Tree.canRot({ daysTotallyRotten = 0 }))
        assert.is_false(Tree.canRot({ canned = true }))
        assert.is_false(Tree.canRot({ packaged = true }))
        assert.is_false(Tree.canRot({ canAge = false, daysTotallyRotten = 8 }))
        assert.is_true(Tree.canRot({ canAge = true }))
        assert.is_false(Tree.canRot(nil))
    end)
end)

describe("filter tree", function()
    it("lists categories and items, including an item from another mod", function()
        local tree = toolTree()
        assert.are.equal("Tool", tree.categories[1].id)
        assert.are.equal("Widget", tree.categories[2].id)
        assert.are.equal(3, #tree.categories[1].items)
        assert.are.equal("OtherMod.Widget", tree.byType["OtherMod.Widget"].category == "Widget" and "OtherMod.Widget" or nil)
        assert.are.equal("Widget", tree.byType["OtherMod.Widget"].category)
    end)

    it("puts food that can rot under Perishable and food that cannot under Non-perishable", function()
        local tree = Tree.build({
            script("Base.Apple", "Food", "Apple", { canRot = true }),
            script("Base.TinnedBeans", "Food", "Canned Beans", { canRot = false, canned = true }),
            script("Base.Hammer", "Tool", "Hammer"),
        })
        assert.are.equal("Food", tree.categories[1].id)
        assert.are.equal("Perishable", tree.categories[1].groups[1].label)
        assert.are.equal("Frozen", tree.categories[1].groups[2].label)
        assert.are.equal("Non-perishable", tree.categories[1].groups[3].label)
        assert.are.equal("Base.Apple", tree.categories[1].groups[1].items[1].id)
        assert.are.equal(0, #tree.categories[1].groups[2].items)
        assert.are.equal("Base.TinnedBeans", tree.categories[1].groups[3].items[1].id)
        assert.is_nil(tree.categories[2].groups)
    end)

    it("shows a partial mark when a ticked category has one item unticked", function()
        local tree = toolTree()
        local all = Tree.setCategory({}, tree, "Tool", true)
        assert.are.equal("on", Tree.mark(all, tree, "Tool"))
        local partial = Tree.setItem(all, tree, "Base.Saw", false)
        assert.are.equal("partial", Tree.mark(partial, tree, "Tool"))
        assert.is_true(partial.categories.Tool)
        assert.is_true(partial.excluded["Base.Saw"])
        assert.is_true(Tree.itemAccepted(partial, tree, "Base.Hammer"))
        assert.is_false(Tree.itemAccepted(partial, tree, "Base.Saw"))
        assert.are.equal(0, Filter.specificity(partial, { category = "Tool", type = "Base.Saw" }))
        assert.are.equal(1, Filter.specificity(partial, { category = "Tool", type = "Base.Hammer" }))
    end)

    it("keeps a single item tick off the category so it stays more specific", function()
        local tree = toolTree()
        local only = Tree.setItem({}, tree, "Base.Hammer", true)
        assert.are.equal("partial", Tree.mark(only, tree, "Tool"))
        assert.is_nil(only.categories.Tool)
        assert.is_true(only.items["Base.Hammer"])
        assert.are.equal(2, Filter.specificity(only, { category = "Tool", type = "Base.Hammer" }))
        assert.are.equal(0, Filter.specificity(only, { category = "Tool", type = "Base.Saw" }))
    end)

    it("treats a step 3 category tick as the whole category, including its items", function()
        local tree = Tree.build(foodScripts(2, true))
        tree = Tree.build({
            script("Base.Apple", "Food", "Apple", { canRot = true }),
            script("Base.TinnedBeans", "Food", "Canned Beans", { canRot = false }),
        })
        local old = { categories = { Food = true } }
        assert.are.equal("on", Tree.mark(old, tree, "Food"))
        assert.are.equal("on", Tree.mark(old, tree, "Food.Perishable"))
        assert.are.equal("on", Tree.mark(old, tree, "Food.Frozen"))
        assert.is_true(Tree.itemAccepted(old, tree, "Base.Apple"))
        assert.is_true(Tree.itemAccepted(old, tree, "Base.TinnedBeans"))
        assert.are.equal("Food: 2 items", Tree.summary(old, tree))
    end)

    it("narrows the tree to rows whose names match the search", function()
        local tree = toolTree()
        local closed = Tree.rows(tree, {}, "", {})
        assert.are.same({ "Tool", "Widget" }, labelsOf(closed))
        local open = Tree.rows(tree, {}, "", { Tool = true })
        assert.are.same({ "Tool", "Hammer", "Saw", "Screws", "Widget" }, labelsOf(open))
        local found = Tree.rows(tree, {}, "screw", {})
        assert.are.same({ "Tool", "Screws" }, labelsOf(found))
        local none = Tree.rows(tree, {}, "nope", {})
        assert.are.same({}, labelsOf(none))
    end)

    it("summarizes a whole category as a count and a few items by name", function()
        local foods = foodScripts(12, true)
        local tree = Tree.build(foods)
        local all = Tree.allowAll(tree)
        assert.are.equal("Food: 12 items", Tree.summary(all, tree))
        local tools = toolTree()
        local copied = Tree.fromContents({ "Base.Screws", "Base.Hammer", "Base.Hammer", "", "not a\nline" })
        assert.is_true(copied.items["Base.Hammer"])
        assert.is_true(copied.items["Base.Screws"])
        assert.is_nil(copied.items[""])
        assert.is_nil(next(copied.categories))
        assert.are.equal("Hammer, Screws", Tree.summary(copied, tools))
        assert.are.equal("No filter", Tree.summary(Tree.clearAll(), tools))
        local one = Tree.setItem({}, tree, "Base.Food1", true)
        assert.are.equal("Food 1", Tree.summary(one, tree))
    end)

    it("ticks every category on Allow All and none on Clear All", function()
        local tree = toolTree()
        local all = Tree.allowAll(tree)
        assert.is_true(all.categories.Tool)
        assert.is_true(all.categories.Widget)
        assert.are.equal("on", Tree.mark(all, tree, "Tool"))
        local cleared = Tree.clearAll()
        assert.are.equal("off", Tree.mark(cleared, tree, "Tool"))
        assert.is_true(Filter.isEmpty(cleared))
    end)

    it("drops one food group out of a ticked Food category without keeping the parent", function()
        local tree = Tree.build({
            script("Base.Apple", "Food", "Apple", { canRot = true }),
            script("Base.TinnedBeans", "Food", "Canned Beans", { canRot = false }),
        })
        local all = Tree.setCategory({}, tree, "Food", true)
        local noFrozen = Tree.setCategory(all, tree, "Food.Frozen", false)
        assert.is_nil(noFrozen.categories.Food)
        assert.is_true(noFrozen.categories["Food.Perishable"])
        assert.is_nil(noFrozen.categories["Food.Frozen"])
        assert.is_true(noFrozen.categories["Food.NonPerishable"])
        assert.are.equal("partial", Tree.mark(noFrozen, tree, "Food"))
    end)

    it("builds the tree once and then returns the cached table", function()
        Tree.resetCache()
        local calls = 0
        local function load()
            calls = calls + 1
            return { script("Base.Hammer", "Tool", "Hammer") }
        end
        local first = Tree.cached(load)
        local second = Tree.cached(function()
            calls = calls + 1
            return {}
        end)
        assert.are.equal(1, calls)
        assert.are.equal(first, second)
        assert.are.equal(1, second.itemCount)
        Tree.resetCache()
    end)

    it("builds a row from a script object and still does not call hasTag", function()
        local calls = 0
        local tree = Tree.build({
            {
                hasTag = function()
                    calls = calls + 1
                    error("No implementation found for function")
                end,
                getFullName = function()
                    return "OtherMod.Widget"
                end,
                getDisplayCategory = function()
                    return "Widget"
                end,
                getDisplayName = function()
                    return "Widget"
                end,
            },
        })
        assert.are.equal(0, calls)
        assert.are.equal("Widget", tree.byType["OtherMod.Widget"].label)
        assert.are.equal("Widget", tree.byType["OtherMod.Widget"].category)
    end)

    it("does not pass a string to hasTag", function()
        local calls = {}
        local item = {
            hasTag = function(_, arg)
                calls[#calls + 1] = arg
                if type(arg) == "string" then
                    error("No implementation found for function")
                end
                return false
            end,
            getFullType = function()
                return "Base.Apple"
            end,
            getDisplayCategory = function()
                return "Food"
            end,
            getDisplayName = function()
                return "Apple"
            end,
            IsFood = function()
                return true
            end,
            isFrozen = function()
                return false
            end,
            getDaysTotallyRotten = function()
                return 6
            end,
            canAge = function()
                return true
            end,
            isPackaged = function()
                return false
            end,
        }
        local facts = Tree.factsFromObject(item)
        assert.are.equal(0, #calls)
        assert.are.equal("Base.Apple", facts.fullType)
        assert.is_true(facts.food)
        assert.is_true(facts.canRot)
        assert.is_false(facts.frozen)
        assert.are.equal("perishable", Tree.foodGroup(facts))
        local frozen = {
            hasTag = item.hasTag,
            getFullType = item.getFullType,
            getDisplayCategory = item.getDisplayCategory,
            getDisplayName = item.getDisplayName,
            IsFood = item.IsFood,
            isFrozen = function()
                return true
            end,
            getDaysTotallyRotten = item.getDaysTotallyRotten,
            canAge = item.canAge,
            isPackaged = item.isPackaged,
        }
        assert.are.equal("frozen", Tree.foodGroup(Tree.factsFromObject(frozen)))
        assert.are.equal(0, #calls)
        local canned = {
            hasTag = function()
                error("No implementation found for function")
            end,
            getFullName = function()
                return "Base.TinnedBeans"
            end,
            getDisplayCategory = function()
                return "Food"
            end,
            getDisplayName = function()
                return "Canned Beans"
            end,
            cannedFood = true,
            canAge = function()
                return false
            end,
        }
        local cannedFacts = Tree.factsFromObject(canned)
        assert.is_true(cannedFacts.food)
        assert.is_false(cannedFacts.canRot)
        assert.are.equal("nonperishable", Tree.foodGroup(cannedFacts))
    end)
end)
