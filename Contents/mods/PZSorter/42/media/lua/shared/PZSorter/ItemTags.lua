-- Turning "does the player have a hammer and a saw?" into a list of tag
-- names the pure dismantle check already understands.
--
-- Build 42.21's inventory methods (containsTag, containsTagRecurse) take an
-- ItemTag object. A plain string throws "expected argument of type ItemTag,
-- got String" and that throw was taking down the whole right-click menu.
-- The static fields (ItemTag.HAMMER, ItemTag.SAW, and so on) are the ones
-- the game exposes to Lua. Every lookup is inside pcall.

PZSorter = PZSorter or {}
PZSorter.ItemTags = PZSorter.ItemTags or {}

local ItemTags = PZSorter.ItemTags

-- Field name on ItemTag, the string hasRequiredTools recognises, and a
-- script id to try with ItemTag.get if the field is missing.
ItemTags.TOOLS = {
    { field = "HAMMER", name = "base:hammer" },
    { field = "SAW", name = "base:saw" },
    { field = "SMALL_SAW", name = "base:smallsaw" },
    { field = "CRUDE_SAW", name = "base:crudesaw" },
    { field = "METAL_SAW", name = "base:metalsaw" },
}

-- ItemTag.get takes a ResourceLocation, not a string. Passing the script id
-- "base:hammer" throws the same "no implementation for String" error that
-- hasTag("Key") throws, and pcall does not hide that stack trace.
function ItemTags.lookup(entry, api)
    if type(entry) ~= "table" then
        return nil
    end
    local tags = api and api.ItemTag or ItemTag
    local locations = api and api.ResourceLocation or ResourceLocation
    if tags and entry.field and tags[entry.field] ~= nil and type(tags[entry.field]) ~= "string" then
        return tags[entry.field]
    end
    if not tags or type(tags.get) ~= "function" then
        return nil
    end
    if not locations or type(locations.of) ~= "function" then
        return nil
    end
    local located, location = pcall(locations.of, entry.name)
    if not located or location == nil or type(location) == "string" then
        return nil
    end
    local got, tag = pcall(tags.get, location)
    if got and tag then
        return tag
    end
    return nil
end

local function lookup(entry)
    return ItemTags.lookup(entry)
end

local function inventoryHas(inventory, tag)
    if not inventory or not tag then
        return false
    end
    local ok, found = pcall(function()
        if inventory.containsTagRecurse then
            return inventory:containsTagRecurse(tag)
        end
        if inventory.containsTag then
            return inventory:containsTag(tag)
        end
        return false
    end)
    return ok and found and true or false
end

-- Returns a list of "base:hammer" / "base:saw" strings, or an empty list.
-- Never throws. A hacksaw is covered when the item carries base:saw or
-- base:metalsaw, which is how those tools are tagged.
function ItemTags.held(inventory)
    local found = {}
    if not inventory then
        return found
    end
    for i = 1, #ItemTags.TOOLS do
        local entry = ItemTags.TOOLS[i]
        local ok, has = pcall(function()
            return inventoryHas(inventory, lookup(entry))
        end)
        if ok and has then
            found[#found + 1] = entry.name
        end
    end
    return found
end

return ItemTags