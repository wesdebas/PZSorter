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

local function lookup(entry)
    if ItemTag and ItemTag[entry.field] then
        return ItemTag[entry.field]
    end
    if not ItemTag or not ItemTag.get then
        return nil
    end
    local ok, tag = pcall(ItemTag.get, entry.name)
    if ok and tag then
        return tag
    end
    if ResourceLocation and ResourceLocation.of then
        ok, tag = pcall(function()
            return ItemTag.get(ResourceLocation.of(entry.name))
        end)
        if ok and tag then
            return tag
        end
    end
    return nil
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