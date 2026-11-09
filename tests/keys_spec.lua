local Keys = require("PZSorter.Keys")

local function tool(fullType)
    return {
        getFullType = function()
            return fullType
        end,
        getCategory = function()
            return "Tool"
        end,
        getDisplayCategory = function()
            return "Tool"
        end,
        hasTag = function(_, arg)
            if type(arg) == "string" then
                error("No implementation found for function: hasTag(ComboItem, String)")
            end
            return false
        end,
    }
end

describe("key check", function()
    local previous

    before_each(function()
        previous = _G.ItemTag
    end)

    after_each(function()
        _G.ItemTag = previous
    end)

    it("does not call hasTag with a string, even when every published tag is a string", function()
        -- The game publishes ItemTag as a global. The spec sandbox does not.
        _G.ItemTag = {
            BUILDING_KEY = "Key",
            CAR_KEY = "key",
            KEY_RING = "KeyRing",
            KEY = "Key",
        }
        assert.is_false(Keys.isKey(tool("Base.Fleshing_Tool_Bone")))
        assert.is_false(Keys.isKey(tool("Base.ClayTool")))
    end)

    it("still recognises a real key by its type, category, or ItemTag object", function()
        _G.ItemTag = nil
        assert.is_true(Keys.isKey(tool("Base.Key1")))
        assert.is_true(Keys.isKey(tool("Base.CarKey")))
        assert.is_true(Keys.isKey({
            getFullType = function()
                return "Base.KeyRing"
            end,
            getCategory = function()
                return "Container"
            end,
        }))
        assert.is_true(Keys.isKey({
            getCategory = function()
                return "Key"
            end,
            getFullType = function()
                return "Mod.HouseKey"
            end,
        }))
        local car = {}
        _G.ItemTag = { CAR_KEY = car, BUILDING_KEY = {}, KEY_RING = {} }
        local calls = {}
        local tagged = {
            getFullType = function()
                return "Base.Padlock"
            end,
            getCategory = function()
                return "Security"
            end,
            getDisplayCategory = function()
                return "Security"
            end,
            hasTag = function(_, arg)
                calls[#calls + 1] = arg
                if type(arg) == "string" then
                    error("No implementation found for function: hasTag(ComboItem, String)")
                end
                return arg == car
            end,
        }
        assert.is_true(Keys.isKey(tagged))
        assert.is_true(#calls > 0)
        for i = 1, #calls do
            assert.are_not.equal("string", type(calls[i]))
        end
    end)
end)
