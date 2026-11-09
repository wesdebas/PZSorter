local Filter = require("PZSorter.Filter")

describe("filter format", function()
    it("treats a missing or empty filter as accepting nothing", function()
        assert.is_true(Filter.isEmpty(nil))
        assert.is_true(Filter.isEmpty({}))
        assert.is_true(Filter.isEmpty({ categories = {}, items = {}, excluded = {} }))
        assert.is_false(Filter.accepts({}, { category = "Food", type = "Base.Apple" }))
        assert.is_false(Filter.accepts(nil, { category = "Food" }))
        assert.are.equal("No filter", Filter.summary({}))
        assert.are.equal("No filter", Filter.summary(nil))
        assert.are.equal(0, Filter.specificity({}, { category = "Food", type = "Base.Apple" }))
    end)

    it("keeps categories, ticked types, and unticked types", function()
        local filter = {
            categories = { Food = true, Tools = true },
            items = { ["Base.Hammer"] = true },
            excluded = { ["Base.CannedBeans"] = true },
        }
        assert.is_true(Filter.accepts(filter, { category = "Food", type = "Base.Apple" }))
        assert.is_true(Filter.accepts(filter, { category = "Tools", type = "Base.Saw" }))
        assert.is_false(Filter.accepts(filter, { category = "Food", type = "Base.CannedBeans" }))
        assert.is_true(Filter.accepts(filter, { category = "Weapon", type = "Base.Hammer" }))
        assert.is_false(Filter.accepts(filter, { category = "Weapon", type = "Base.Axe" }))
        assert.are.equal(1, Filter.specificity(filter, { category = "Food", type = "Base.Apple" }))
        assert.are.equal(2, Filter.specificity(filter, { category = "Weapon", type = "Base.Hammer" }))
        assert.are.equal(0, Filter.specificity(filter, { category = "Food", type = "Base.CannedBeans" }))
    end)

    it("does not call an individual tick more specific when the whole category is ticked", function()
        local filter = {
            categories = { Tools = true },
            items = { ["Base.Hammer"] = true },
        }
        assert.are.equal(1, Filter.specificity(filter, { category = "Tools", type = "Base.Hammer" }))
    end)

    it("lets an exclusion beat an individual tick", function()
        local filter = {
            items = { ["Base.Hammer"] = true },
            excluded = { ["Base.Hammer"] = true },
        }
        assert.are.equal(0, Filter.specificity(filter, { category = "Tools", type = "Base.Hammer" }))
        assert.is_false(Filter.accepts(filter, { type = "Base.Hammer" }))
    end)

    it("reads a set, a fresh list, and the string keys a save writes", function()
        local fromSet = Filter.normalize({ categories = { Food = true } })
        assert.is_true(fromSet.categories.Food)
        local fromList = Filter.normalize({ categories = { "Tools", "Food" } })
        assert.is_true(fromList.categories.Food)
        assert.is_true(fromList.categories.Tools)
        local saved = Filter.normalize({
            categories = { ["1"] = "Food", ["2"] = "Tools" },
            items = { ["1"] = "Base.Hammer" },
            excluded = { ["1"] = "Base.Saw" },
        })
        assert.is_true(saved.categories.Food)
        assert.is_true(saved.categories.Tools)
        assert.is_true(saved.items["Base.Hammer"])
        assert.is_true(saved.excluded["Base.Saw"])
        assert.is_true(Filter.accepts(saved, { category = "Food", type = "Base.Apple" }))
        assert.is_false(Filter.accepts(saved, { category = "Tools", type = "Base.Saw" }))
    end)

    it("summarizes ticked categories in order, and says No filter when there are none", function()
        assert.are.equal("Food", Filter.summary({ categories = { Food = true } }))
        assert.are.equal("Food, Tools", Filter.summary({ categories = { Tools = true, Food = true } }))
        assert.are.equal("Food, Tools", Filter.summary({ categories = { "Tools", "Food" } }))
        local labeled = Filter.summary(
            { categories = { Tools = true, Food = true } },
            { Tools = "Zebra", Food = "Apple" }
        )
        assert.are.equal("Apple, Zebra", labeled)
    end)

    it("does not call an item-only filter empty", function()
        local filter = { items = { ["Base.Hammer"] = true } }
        assert.is_false(Filter.isEmpty(filter))
        assert.are.equal("Base.Hammer", Filter.summary(filter))
        assert.are.same({ "Food" }, Filter.categoryNames({ categories = { Food = true } }))
        assert.are.same({ "Food", "Tools" }, Filter.categoryNames({ categories = { Tools = true, Food = true } }))
    end)

    it("replaces categories and keeps item ticks and exclusions", function()
        local original = {
            categories = { Food = true },
            items = { ["Base.Hammer"] = true },
            excluded = { ["Base.Saw"] = true },
        }
        local updated = Filter.withCategories(original, { "Tools", "Ammo" })
        assert.is_true(original.categories.Food)
        assert.is_nil(updated.categories.Food)
        assert.is_true(updated.categories.Tools)
        assert.is_true(updated.categories.Ammo)
        assert.is_true(updated.items["Base.Hammer"])
        assert.is_true(updated.excluded["Base.Saw"])
        assert.are.equal("Ammo, Tools", Filter.summary(updated))
        local cleared = Filter.withCategories(updated, {})
        assert.are.equal("Base.Hammer", Filter.summary(cleared))
        local fullyClear = Filter.withCategories({ categories = { Food = true } }, {})
        assert.are.equal("No filter", Filter.summary(fullyClear))
        assert.is_true(Filter.isEmpty(fullyClear))
    end)

    it("replaces every set, which is how an item tick is saved", function()
        local old = Filter.normalize({ categories = { ["1"] = "Food" } })
        assert.is_true(old.categories.Food)
        assert.is_true(Filter.accepts(old, { category = "Food", type = "Base.Apple" }))
        local replaced = Filter.replace({
            categories = Filter.parseList("Tool"),
            items = Filter.parseList("Base.Hammer"),
            excluded = Filter.parseList("Base.Saw"),
        })
        assert.is_nil(replaced.categories.Food)
        assert.is_true(replaced.categories.Tool)
        assert.is_true(replaced.items["Base.Hammer"])
        assert.is_true(replaced.excluded["Base.Saw"])
        assert.are.equal(2, Filter.specificity(replaced, { category = "Weapon", type = "Base.Hammer" }))
        assert.are.equal(0, Filter.specificity(replaced, { category = "Tool", type = "Base.Saw" }))
        local cleared = Filter.replace({
            categories = Filter.parseList(""),
            items = Filter.parseList(""),
            excluded = Filter.parseList(""),
        })
        assert.are.equal("No filter", Filter.summary(cleared))
        assert.is_true(Filter.isEmpty(cleared))
    end)

    it("parses a newline list and treats an empty one as Clear All", function()
        assert.are.same({}, Filter.parseList(nil))
        assert.are.same({}, Filter.parseList(""))
        assert.are.same({ "Food", "Tools" }, Filter.parseList("Food\nTools"))
        assert.are.same({ "Food", "Tools" }, Filter.parseList("Food\n\nTools\n"))
        local updated = Filter.withCategories({}, Filter.parseList("Food\nTools"))
        assert.are.equal("Food, Tools", Filter.summary(updated))
        local cleared = Filter.withCategories(updated, Filter.parseList(""))
        assert.are.equal("No filter", Filter.summary(cleared))
    end)
end)
