local ItemTags = require("PZSorter.ItemTags")

describe("item tag lookup", function()
    it("does not pass a string to ItemTag.get", function()
        local calls = {}
        local location = { path = "base:hammer" }
        local api = {
            ItemTag = {
                get = function(id)
                    calls[#calls + 1] = id
                    if type(id) == "string" then
                        error("No implementation found for function: get(String)")
                    end
                    return { id = id }
                end,
            },
            ResourceLocation = {
                of = function(name)
                    assert.are.equal("base:hammer", name)
                    return location
                end,
            },
        }
        local tag = ItemTags.lookup({ field = "HAMMER", name = "base:hammer" }, api)
        assert.are.equal(location, tag.id)
        assert.are.equal(1, #calls)
        assert.are.equal(location, calls[1])
    end)

    it("uses a published ItemTag field and does not call get", function()
        local hammer = { name = "hammer" }
        local api = {
            ItemTag = {
                HAMMER = hammer,
                get = function()
                    error("get should not be called")
                end,
            },
        }
        assert.are.equal(hammer, ItemTags.lookup({ field = "HAMMER", name = "base:hammer" }, api))
    end)
end)
