-- What a linked container is willing to take.
--
-- The save shape is the one in the design spec: a set of ticked categories,
-- a set of ticked item types, and a set of unticked item types under ticked
-- categories. A step 3 save only has categories. Loading it still means
-- "the whole category", and saving again writes the same three sets.
--
-- An empty filter accepts nothing. The panel says "No filter" for that row.
-- A missing filter, and the {} stored when a container is first assigned,
-- are empty.
--
-- The game's save sometimes rewrites a Lua array as string keys ("1", "2").
-- The same thing happened to the link list. Reading a set accepts a real
-- set ({ Food = true }), a fresh array ({ "Food" }), and that saved shape.

PZSorter = PZSorter or {}
PZSorter.Filter = PZSorter.Filter or {}

local Filter = PZSorter.Filter

-- Shown on a row that has nothing ticked. The English text is the spec's.
Filter.NONE = "No filter"

local function cleanToken(text)
    if type(text) ~= "string" then
        return nil
    end
    if text == "" or #text > 128 then
        return nil
    end
    -- Category names and item types are single tokens. A control character
    -- would mean a bad packet, not a real category.
    if text:find("%c") then
        return nil
    end
    return text
end

-- Turn whatever was saved into a set of strings.
local function readSet(value)
    local set = {}
    if type(value) ~= "table" then
        return set
    end
    local numbered = {}
    for key, entry in pairs(value) do
        local index = tonumber(key)
        local token = cleanToken(entry)
        if index and token then
            numbered[#numbered + 1] = { index = index, token = token }
        elseif type(key) == "string" and not tonumber(key) then
            local name = cleanToken(key)
            if name and (entry == true or entry == 1) then
                set[name] = true
            end
        end
    end
    table.sort(numbered, function(a, b)
        return a.index < b.index
    end)
    for i = 1, #numbered do
        set[numbered[i].token] = true
    end
    return set
end

function Filter.normalize(filter)
    if type(filter) ~= "table" then
        filter = {}
    end
    return {
        categories = readSet(filter.categories),
        items = readSet(filter.items),
        excluded = readSet(filter.excluded),
    }
end

-- Nothing ticked. Excluded types alone still accept nothing, because there
-- is no category or item for them to carve a hole in.
function Filter.isEmpty(filter)
    local normalized = Filter.normalize(filter)
    return next(normalized.categories) == nil and next(normalized.items) == nil
end

-- 0 does not accept the item.
-- 1 is a ticked category, or a ticked food sub-group (the whole group,
--    even if this type is also ticked on its own).
-- 2 is this type ticked on its own, and neither its category nor its food
--    sub-group is ticked. That is the specific match: Hammer in one box
--    beats Tool in another.
function Filter.specificity(filter, item)
    if type(item) ~= "table" then
        return 0
    end
    local normalized = Filter.normalize(filter)
    local typeName = cleanToken(item.type or item.fullType)
    local category = cleanToken(item.category)
    if typeName and normalized.excluded[typeName] then
        return 0
    end
    local categoryOn = category and normalized.categories[category] or false
    local groupOn = false
    local Tree = PZSorter.FilterTree
    if Tree and Tree.foodCategory then
        local groupId = Tree.foodCategory(item)
        if groupId and normalized.categories[groupId] then
            groupOn = true
        end
    end
    local itemOn = typeName and normalized.items[typeName] or false
    if itemOn and not categoryOn and not groupOn then
        return 2
    end
    if categoryOn or groupOn then
        return 1
    end
    return 0
end

function Filter.accepts(filter, item)
    return Filter.specificity(filter, item) > 0
end

local function sortedNames(set, labels)
    local names = {}
    for name in pairs(set) do
        names[#names + 1] = name
    end
    table.sort(names)
    if type(labels) == "table" then
        for i = 1, #names do
            local label = labels[names[i]]
            if type(label) == "string" and label ~= "" then
                names[i] = label
            end
        end
        table.sort(names)
    end
    return names
end

-- "Food" or "Food, Tools". Labels are optional display names (the game's
-- translated category). Without them, the stored ids are shown, in order.
function Filter.summary(filter, labels)
    local normalized = Filter.normalize(filter)
    local names = sortedNames(normalized.categories, labels)
    if #names == 0 then
        -- A filter that only ticks item types is not empty. This step does
        -- not write those, but a later step will, and the row should not
        -- claim there is no filter.
        names = sortedNames(normalized.items, labels)
    end
    if #names == 0 then
        return Filter.NONE
    end
    return table.concat(names, ", ")
end

function Filter.categoryNames(filter)
    return sortedNames(Filter.normalize(filter).categories, nil)
end

-- Write all three sets. The item editor sends every set, including an
-- empty one, so Clear All really clears. A missing argument is an empty
-- set, not "leave the old one".
function Filter.replace(parts)
    if type(parts) ~= "table" then
        parts = {}
    end
    return {
        categories = readSet(parts.categories),
        items = readSet(parts.items),
        excluded = readSet(parts.excluded),
    }
end

-- Replace the ticked categories. Item ticks and exclusions stay, so an
-- old category-only packet does not wipe item ticks.
function Filter.withCategories(filter, names)
    local current = Filter.normalize(filter)
    return {
        categories = readSet(names),
        items = current.items,
        excluded = current.excluded,
    }
end

-- The checklist sends one category per line. An empty string is Clear All.
-- A newline cannot appear in a category id, so this survives the client
-- command even when an empty table would be dropped on the way.
function Filter.parseList(text)
    local names = {}
    if type(text) ~= "string" or text == "" then
        return names
    end
    local rest = text
    while rest ~= "" do
        local line, tail = rest:match("^([^\n]*)\n(.*)$")
        if not line then
            line = rest
            rest = ""
        else
            rest = tail
        end
        local token = cleanToken(line)
        if token then
            names[#names + 1] = token
        end
    end
    return names
end

-- Loaded after the functions above so a food sub-group can be part of
-- specificity. FilterTree does not require this file back.
require "PZSorter/FilterTree"

return Filter
