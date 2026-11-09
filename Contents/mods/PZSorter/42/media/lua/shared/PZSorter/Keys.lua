-- Is this item a key, or a key ring that would carry keys with it?
--
-- Build 42's InventoryItem:hasTag takes an ItemTag, not a Lua string.
-- hasTag("Key") throws "No implementation found for function: hasTag(..., String)"
-- and the game still prints that stack trace when pcall catches it. This
-- file never passes a string to hasTag. It uses the Key and KeyRing classes,
-- the category, the item type, and the ItemTag fields the game actually
-- publishes (BUILDING_KEY, CAR_KEY, KEY_RING).

PZSorter = PZSorter or {}
PZSorter.Keys = PZSorter.Keys or {}

local Keys = PZSorter.Keys

local function callMethod(object, method)
    if object == nil then
        return nil
    end
    local fn = object[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, object)
    if ok then
        return value
    end
    return nil
end

local function asText(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

local function shortType(full)
    if not full then
        return ""
    end
    return full:match("([^%.]+)$") or full
end

local function isClass(item, className)
    if type(instanceof) ~= "function" then
        return false
    end
    local ok, result = pcall(instanceof, item, className)
    return ok and result and true or false
end

-- A name the game uses for a key. "ClayTool" and "Fleshing_Tool_Bone"
-- do not match. A word that merely contains the letters "key" does not either.
local function nameIsKey(short)
    if short == "Key" or short == "KeyRing" then
        return true
    end
    if short:match("^Key%d") or short:match("^CarKey") or short:match("KeyRing$") then
        return true
    end
    return false
end

local function publishedTags()
    local tags = {}
    if not ItemTag then
        return tags
    end
    local fields = { "BUILDING_KEY", "CAR_KEY", "KEY_RING" }
    for i = 1, #fields do
        local tag = ItemTag[fields[i]]
        -- A string here would be the bug. hasTag does not accept one.
        if tag ~= nil and type(tag) ~= "string" then
            tags[#tags + 1] = tag
        end
    end
    return tags
end

function Keys.isKey(item)
    if item == nil then
        return false
    end
    if isClass(item, "Key") or isClass(item, "KeyRing") then
        return true
    end
    local category = asText(callMethod(item, "getCategory"))
    if category == "Key" then
        return true
    end
    local display = asText(callMethod(item, "getDisplayCategory"))
    if display == "Key" then
        return true
    end
    local full = asText(callMethod(item, "getFullType"))
    if nameIsKey(shortType(full)) then
        return true
    end
    local hasTag = item.hasTag
    if type(hasTag) ~= "function" then
        return false
    end
    local tags = publishedTags()
    for i = 1, #tags do
        local ok, tagged = pcall(hasTag, item, tags[i])
        if ok and tagged then
            return true
        end
    end
    return false
end

return Keys
