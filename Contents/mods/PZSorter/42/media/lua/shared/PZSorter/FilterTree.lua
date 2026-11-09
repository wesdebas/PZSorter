-- The filter tree: categories, the items in them, and the food sub-groups.
--
-- Built from the game's item list, so an item added by another mod shows
-- up too. The tree is built once and cached. Ticks are not stored here.
-- They stay on the container filter (categories, items, excluded). This
-- file only answers "what is in the tree", "is this box ticked, empty, or
-- partial", and "what should the row say".
--
-- No game call is required to test it. Pass plain item tables, or a mock
-- whose hasTag throws if anyone hands it a string. Build 42's hasTag only
-- accepts an ItemTag. This file never calls hasTag.

PZSorter = PZSorter or {}
PZSorter.FilterTree = PZSorter.FilterTree or {}

local Tree = PZSorter.FilterTree

-- Display category the inventory uses for food. The three sub-groups below
-- are ours. They are stored as category ids so a step 3 save, which only
-- has real categories, still loads.
Tree.FOOD = "Food"
Tree.PERISHABLE = "Food.Perishable"
Tree.FROZEN = "Food.Frozen"
Tree.NONPERISHABLE = "Food.NonPerishable"

Tree.GROUP_PERISHABLE = "perishable"
Tree.GROUP_FROZEN = "frozen"
Tree.GROUP_NONPERISHABLE = "nonperishable"

Tree.ON = "on"
Tree.OFF = "off"
Tree.PARTIAL = "partial"

-- DaysTotallyRotten at or above this means the game is saying "never".
-- Sealed cans use that sentinel, or they leave the lifetime unset.
Tree.NEVER_ROTS_DAYS = 1000000000

-- Which food sub-group one item belongs in. The three groups do not overlap.
--
-- Open question 5 was not settled. These are the meanings this step uses.
-- Change them here if they should mean something else. Everything that
-- sorts food calls this function, so there is one place to edit.
--
--   Frozen:          food that is frozen right now. Checked first, so a
--                    frozen apple is Frozen and not Perishable, and a
--                    frozen can is Frozen and not Non-perishable.
--   Perishable:      food that can rot and is not frozen right now.
--   Non-perishable:  food that never rots (canned, dry) and is not frozen.
--
-- facts.food    true when it is food. Anything else returns nil.
-- facts.frozen  true when that food is frozen right now.
-- facts.canRot  true when that kind of food can rot. See canRot below
--               for how a script or a live item becomes that flag.
function Tree.foodGroup(facts)
    if type(facts) ~= "table" or not facts.food then
        return nil
    end
    if facts.frozen then
        return Tree.GROUP_FROZEN
    end
    if facts.canRot then
        return Tree.GROUP_PERISHABLE
    end
    return Tree.GROUP_NONPERISHABLE
end

-- The category id for that group, or nil when the item is not food.
function Tree.foodCategory(item)
    local group = Tree.foodGroup(item)
    if group == Tree.GROUP_PERISHABLE then
        return Tree.PERISHABLE
    end
    if group == Tree.GROUP_FROZEN then
        return Tree.FROZEN
    end
    if group == Tree.GROUP_NONPERISHABLE then
        return Tree.NONPERISHABLE
    end
    return nil
end

-- Does this kind of food rot? This is how a script or a live item becomes
-- facts.canRot. It is not the group meaning. Wes changes the groups in
-- foodGroup. Change this only when the game's numbers are being read wrong.
--
--   canAge == false                         never rots (the game's own flag)
--   a rot lifetime above 0 and below the    can rot, including an opened can
--     never-rots sentinel
--   canned or still packaged, no lifetime   never rots (sealed can, dry food)
--   canAge == true and no lifetime          can rot
--   anything else                           never rots
function Tree.canRot(facts)
    if type(facts) ~= "table" then
        return false
    end
    if facts.canAge == false then
        return false
    end
    local days = tonumber(facts.daysTotallyRotten)
    if days == nil then
        days = tonumber(facts.offAgeMax)
    end
    if days and days > 0 and days < Tree.NEVER_ROTS_DAYS then
        return true
    end
    if facts.canned == true or facts.packaged == true then
        return false
    end
    if facts.canAge == true then
        return true
    end
    return false
end

local function field(object, name)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    if ok then
        return value
    end
    return nil
end

local function call(object, method)
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
    if type(value) == "string" then
        if value == "" then
            return nil
        end
        return value
    end
    if value == nil then
        return nil
    end
    if (type(value) == "userdata" or type(value) == "table") and type(value.toString) == "function" then
        local ok, text = pcall(value.toString, value)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    return nil
end

local function isFoodTypeName(text)
    if type(text) ~= "string" then
        return false
    end
    return text == "Food" or text:match("%.Food$") ~= nil or text:match(":Food$") ~= nil
end

-- Facts for one script or one live item. Uses the class, the display
-- category, the type, and the rot numbers. Never calls hasTag: on Build 42
-- that function throws when the argument is a string.
function Tree.factsFromObject(object)
    local empty = {
        fullType = nil,
        category = nil,
        label = nil,
        food = false,
        canRot = false,
        frozen = false,
    }
    if object == nil or (type(object) ~= "table" and type(object) ~= "userdata") then
        return empty
    end
    local fullType = asText(call(object, "getFullType")) or asText(call(object, "getFullName"))
    if not fullType then
        local moduleName = asText(call(object, "getModule")) or asText(call(object, "getModuleName"))
        local shortType = asText(call(object, "getName"))
        if moduleName and shortType then
            fullType = moduleName .. "." .. shortType
        end
    end
    local category = asText(call(object, "getDisplayCategory"))
    local label = asText(call(object, "getDisplayName"))
    local food = false
    if type(instanceof) == "function" then
        local ok, result = pcall(instanceof, object, "Food")
        if ok and result then
            food = true
        end
    end
    if not food and call(object, "IsFood") then
        food = true
    end
    local typeText = asText(call(object, "getType"))
    if not food and isFoodTypeName(typeText) then
        food = true
    end
    if not food and category == Tree.FOOD then
        food = true
    end
    local days = call(object, "getDaysTotallyRotten")
    if type(days) ~= "number" then
        days = field(object, "daysTotallyRotten")
    end
    if type(days) ~= "number" then
        days = call(object, "getOffAgeMax")
    end
    if type(days) ~= "number" then
        days = field(object, "offAgeMax")
    end
    local script = call(object, "getScriptItem")
    if type(days) ~= "number" and script ~= nil then
        local scriptDays = call(script, "getDaysTotallyRotten")
        if type(scriptDays) == "number" then
            days = scriptDays
        end
    end
    local canned = nil
    local cannedField = field(object, "cannedFood")
    if type(cannedField) == "boolean" then
        canned = cannedField
    end
    if canned == nil and type(script) == "table" and type(script.cannedFood) == "boolean" then
        canned = script.cannedFood
    end
    local canAge = call(object, "canAge")
    local packaged = call(object, "isPackaged")
    local canRot = Tree.canRot({
        daysTotallyRotten = type(days) == "number" and days or nil,
        canAge = canAge,
        packaged = packaged and true or false,
        canned = canned,
    })
    if not food and (canRot or canned == true) then
        food = true
    end
    local frozen = call(object, "isFrozen") and true or false
    return {
        fullType = fullType,
        category = category,
        label = label,
        food = food and true or false,
        canRot = canRot and true or false,
        frozen = frozen,
    }
end

local FALLBACK_CATEGORIES = {
    "Ammo", "Bag", "Clothing", "Food", "Literature", "Medical", "Tool", "Weapon",
}

function Tree.fallbackScripts()
    local scripts = {}
    for i = 1, #FALLBACK_CATEGORIES do
        scripts[i] = { category = FALLBACK_CATEGORIES[i], placeholder = true }
    end
    return scripts
end

local function ensureBucket(buckets, category)
    local bucket = buckets[category]
    if not bucket then
        bucket = { id = category, label = category, items = {} }
        buckets[category] = bucket
    end
    return bucket
end

-- scripts is a list of plain tables (fullType, category, label, canRot,
-- food) or live script objects. Placeholders add an empty category so the
-- food groups still appear when the item list could not be read.
function Tree.build(scripts)
    local buckets = {}
    local byType = {}
    if type(scripts) ~= "table" then
        scripts = {}
    end
    local skipped = 0
    for i = 1, #scripts do
        local script = scripts[i]
        local kind = type(script)
        -- The game's item list is Java objects (userdata), not Lua tables.
        -- A test passes plain tables. Both have to become rows.
        if kind == "table" or kind == "userdata" then
            local facts = script
            local looksLive = kind == "userdata"
                or (kind == "table" and (script.getDisplayCategory or script.getFullType or script.getFullName or script.IsFood))
            if looksLive then
                local readOk, read = pcall(Tree.factsFromObject, script)
                if readOk and type(read) == "table" then
                    facts = read
                else
                    facts = {}
                    skipped = skipped + 1
                end
            end
            if facts.placeholder and type(facts.category) == "string" and facts.category ~= "" and facts.category ~= "Hidden" then
                ensureBucket(buckets, facts.category)
            end
            local fullType = facts.fullType
            local category = facts.category
            if type(fullType) == "string" and fullType ~= "" and not fullType:find("%c")
                and type(category) == "string" and category ~= "" and category ~= "Hidden"
                and not byType[fullType]
            then
                local label = facts.label or facts.displayName
                if type(label) ~= "string" or label == "" then
                    label = fullType:match("([^%.]+)$") or fullType
                end
                local bucket = ensureBucket(buckets, category)
                local groupCategory = nil
                local canRot = facts.canRot
                if category == Tree.FOOD then
                    if canRot == nil then
                        canRot = Tree.canRot(facts)
                    end
                    if canRot then
                        groupCategory = Tree.PERISHABLE
                    else
                        groupCategory = Tree.NONPERISHABLE
                    end
                end
                bucket.items[#bucket.items + 1] = {
                    id = fullType,
                    label = label,
                    groupCategory = groupCategory,
                }
                byType[fullType] = {
                    category = category,
                    label = label,
                    groupCategory = groupCategory,
                }
            end
        end
    end
    if skipped > 0 and type(print) == "function" then
        print("PZSorter: filter tree skipped " .. tostring(skipped) .. " items")
    end
    local categories = {}
    local itemCount = 0
    for _, bucket in pairs(buckets) do
        table.sort(bucket.items, function(a, b)
            return a.label:lower() < b.label:lower()
        end)
        if bucket.id == Tree.FOOD then
            local perishable = {}
            local stable = {}
            for i = 1, #bucket.items do
                local entry = bucket.items[i]
                if entry.groupCategory == Tree.PERISHABLE then
                    perishable[#perishable + 1] = entry
                else
                    stable[#stable + 1] = entry
                end
            end
            bucket.groups = {
                { id = Tree.PERISHABLE, label = "Perishable", items = perishable },
                { id = Tree.FROZEN, label = "Frozen", items = {} },
                { id = Tree.NONPERISHABLE, label = "Non-perishable", items = stable },
            }
        end
        itemCount = itemCount + #bucket.items
        categories[#categories + 1] = bucket
    end
    table.sort(categories, function(a, b)
        return a.label:lower() < b.label:lower()
    end)
    return {
        categories = categories,
        byType = byType,
        itemCount = itemCount,
    }
end

function Tree.readGame()
    local manager = nil
    if type(getScriptManager) == "function" then
        local ok, found = pcall(getScriptManager)
        if ok then
            manager = found
        end
    end
    if (type(manager) ~= "table" and type(manager) ~= "userdata" or type(manager.getAllItems) ~= "function")
        and ScriptManager and ScriptManager.instance
    then
        manager = ScriptManager.instance
    end
    if not manager or type(manager.getAllItems) ~= "function" then
        return Tree.fallbackScripts(), "fallback"
    end
    local ok, all = pcall(manager.getAllItems, manager)
    if not ok or not all then
        return Tree.fallbackScripts(), "fallback"
    end
    -- A Lua array (some test doubles, and an older binding) has no size().
    if type(all) == "table" and type(all.size) ~= "function" then
        if all[1] == nil then
            return Tree.fallbackScripts(), "fallback"
        end
        return all, "game"
    end
    if type(all.size) ~= "function" or type(all.get) ~= "function" then
        return Tree.fallbackScripts(), "fallback"
    end
    local sizeOk, size = pcall(all.size, all)
    if not sizeOk or type(size) ~= "number" or size <= 0 then
        return Tree.fallbackScripts(), "fallback"
    end
    local scripts = {}
    for i = 0, size - 1 do
        local got, script = pcall(all.get, all, i)
        if got and script then
            scripts[#scripts + 1] = script
        end
    end
    if #scripts == 0 then
        return Tree.fallbackScripts(), "fallback"
    end
    return scripts, "game"
end

local cachedTree = nil
local announcedSource = nil

function Tree.resetCache()
    cachedTree = nil
    announcedSource = nil
end

-- Build once from the game's item list. A fallback (the list could not be
-- read yet) is tried again next time, so a later open still sees mod items.
-- A loader is for tests. The same successful table is returned until resetCache.
function Tree.cached(loader)
    if cachedTree and cachedTree.source ~= "fallback" then
        return cachedTree
    end
    local scripts, source
    if type(loader) == "function" then
        scripts = loader()
        source = "loader"
    else
        scripts, source = Tree.readGame()
    end
    if type(scripts) ~= "table" then
        scripts = {}
    end
    cachedTree = Tree.build(scripts)
    cachedTree.source = source or "fallback"
    if source ~= "loader" and announcedSource ~= cachedTree.source and type(print) == "function" then
        announcedSource = cachedTree.source
        print("PZSorter: filter categories=" .. tostring(#cachedTree.categories)
            .. " items=" .. tostring(cachedTree.itemCount)
            .. " source=" .. tostring(cachedTree.source))
    end
    return cachedTree
end

local function findNode(tree, categoryId)
    local categories = tree and tree.categories or {}
    for i = 1, #categories do
        local category = categories[i]
        if category.id == categoryId then
            return category, nil
        end
        local groups = category.groups or {}
        for g = 1, #groups do
            if groups[g].id == categoryId then
                return category, groups[g]
            end
        end
    end
    return nil, nil
end

function Tree.itemIds(tree, categoryId)
    local category, group = findNode(tree, categoryId)
    local items = {}
    if group then
        items = group.items or {}
    elseif category then
        items = category.items or {}
    end
    local ids = {}
    for i = 1, #items do
        ids[i] = items[i].id
    end
    return ids
end

local function normalized(filter)
    local Filter = PZSorter.Filter
    if Filter and Filter.normalize then
        return Filter.normalize(filter)
    end
    return { categories = {}, items = {}, excluded = {} }
end

local function copySet(set)
    local out = {}
    if type(set) ~= "table" then
        return out
    end
    for key, value in pairs(set) do
        if value and type(key) == "string" then
            out[key] = true
        end
    end
    return out
end

local function copyFilter(filter)
    local current = normalized(filter)
    return {
        categories = copySet(current.categories),
        items = copySet(current.items),
        excluded = copySet(current.excluded),
    }
end

local function clearIds(current, ids)
    for i = 1, #ids do
        current.items[ids[i]] = nil
        current.excluded[ids[i]] = nil
    end
end

local function isFoodGroup(categoryId)
    return categoryId == Tree.PERISHABLE or categoryId == Tree.FROZEN or categoryId == Tree.NONPERISHABLE
end

function Tree.itemAccepted(filter, tree, fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return false
    end
    local current = normalized(filter)
    if current.excluded[fullType] then
        return false
    end
    if current.items[fullType] then
        return true
    end
    local meta = tree and tree.byType and tree.byType[fullType]
    if not meta then
        return false
    end
    if meta.category and current.categories[meta.category] then
        return true
    end
    if meta.groupCategory and current.categories[meta.groupCategory] then
        return true
    end
    return false
end

function Tree.mark(filter, tree, categoryId)
    local current = normalized(filter)
    if categoryId == Tree.FROZEN then
        if current.categories[Tree.FOOD] or current.categories[Tree.FROZEN] then
            return Tree.ON
        end
        return Tree.OFF
    end
    local ids = Tree.itemIds(tree, categoryId)
    if #ids == 0 then
        if current.categories[categoryId] then
            return Tree.ON
        end
        if categoryId == Tree.FOOD and (
            current.categories[Tree.PERISHABLE]
            or current.categories[Tree.NONPERISHABLE]
            or current.categories[Tree.FROZEN]
        ) then
            return Tree.PARTIAL
        end
        return Tree.OFF
    end
    local onCount = 0
    for i = 1, #ids do
        if Tree.itemAccepted(current, tree, ids[i]) then
            onCount = onCount + 1
        end
    end
    if onCount == 0 then
        if categoryId == Tree.FOOD and current.categories[Tree.FROZEN] then
            return Tree.PARTIAL
        end
        return Tree.OFF
    end
    if onCount < #ids then
        return Tree.PARTIAL
    end
    if categoryId == Tree.FOOD then
        local coversFrozen = current.categories[Tree.FOOD] or current.categories[Tree.FROZEN]
        if not coversFrozen then
            return Tree.PARTIAL
        end
    end
    return Tree.ON
end

function Tree.setCategory(filter, tree, categoryId, turnOn)
    local current = copyFilter(filter)
    if type(categoryId) ~= "string" or categoryId == "" then
        return current
    end
    local ids = Tree.itemIds(tree, categoryId)
    if turnOn then
        if categoryId == Tree.FOOD then
            current.categories[Tree.FOOD] = true
            current.categories[Tree.PERISHABLE] = nil
            current.categories[Tree.FROZEN] = nil
            current.categories[Tree.NONPERISHABLE] = nil
            clearIds(current, ids)
            return current
        end
        if current.categories[Tree.FOOD] and isFoodGroup(categoryId) then
            return current
        end
        current.categories[categoryId] = true
        clearIds(current, ids)
        return current
    end
    if current.categories[Tree.FOOD] and isFoodGroup(categoryId) then
        -- Food meant all three groups. Unticking one keeps the other two
        -- and drops the parent, so frozen food is not still accepted just
        -- because the parent used to be ticked.
        current.categories[Tree.FOOD] = nil
        current.categories[Tree.PERISHABLE] = categoryId ~= Tree.PERISHABLE and true or nil
        current.categories[Tree.FROZEN] = categoryId ~= Tree.FROZEN and true or nil
        current.categories[Tree.NONPERISHABLE] = categoryId ~= Tree.NONPERISHABLE and true or nil
        clearIds(current, ids)
        return current
    end
    current.categories[categoryId] = nil
    if categoryId == Tree.FOOD then
        current.categories[Tree.PERISHABLE] = nil
        current.categories[Tree.FROZEN] = nil
        current.categories[Tree.NONPERISHABLE] = nil
    end
    clearIds(current, ids)
    return current
end

function Tree.setItem(filter, tree, fullType, turnOn)
    local current = copyFilter(filter)
    if type(fullType) ~= "string" or fullType == "" then
        return current
    end
    local meta = tree and tree.byType and tree.byType[fullType]
    local covered = false
    if meta then
        if meta.category and current.categories[meta.category] then
            covered = true
        end
        if meta.groupCategory and current.categories[meta.groupCategory] then
            covered = true
        end
    end
    if turnOn then
        current.excluded[fullType] = nil
        if not covered then
            current.items[fullType] = true
        end
        return current
    end
    current.items[fullType] = nil
    if covered then
        current.excluded[fullType] = true
    else
        current.excluded[fullType] = nil
    end
    return current
end

function Tree.toggleCategory(filter, tree, categoryId)
    local mark = Tree.mark(filter, tree, categoryId)
    return Tree.setCategory(filter, tree, categoryId, mark ~= Tree.ON)
end

function Tree.toggleItem(filter, tree, fullType)
    local on = Tree.itemAccepted(filter, tree, fullType)
    return Tree.setItem(filter, tree, fullType, not on)
end

function Tree.allowAll(tree)
    local categories = {}
    local list = tree and tree.categories or {}
    for i = 1, #list do
        categories[list[i].id] = true
    end
    return { categories = categories, items = {}, excluded = {} }
end

function Tree.clearAll()
    return { categories = {}, items = {}, excluded = {} }
end

-- Tick exactly these item types. Categories stay off, so each tick is the
-- specific kind of match (a hammer on its own, not the whole Tool category).
function Tree.fromContents(types)
    local items = {}
    if type(types) ~= "table" then
        return { categories = {}, items = items, excluded = {} }
    end
    for i = 1, #types do
        local fullType = types[i]
        if type(fullType) == "string" and fullType ~= "" and not fullType:find("%c") and #fullType <= 128 then
            items[fullType] = true
        end
    end
    return { categories = {}, items = items, excluded = {} }
end

local function contains(text, query)
    if query == "" then
        return true
    end
    if type(text) ~= "string" then
        return false
    end
    return text:lower():find(query, 1, true) ~= nil
end

local function push(rows, kind, id, label, depth, mark, parent)
    rows[#rows + 1] = {
        kind = kind,
        id = id,
        label = label,
        depth = depth,
        mark = mark,
        parent = parent,
    }
end

-- Visible rows. An empty search shows categories, and children only when
-- expanded[id] is true. A search keeps the branches that match and opens
-- them, so typing "screw" shows Tool and Screws and not the other tools.
function Tree.rows(tree, filter, query, expanded)
    local rows = {}
    if type(query) ~= "string" then
        query = ""
    end
    query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if type(expanded) ~= "table" then
        expanded = {}
    end
    local searching = query ~= ""
    local categories = tree and tree.categories or {}
    for c = 1, #categories do
        local category = categories[c]
        local catMatch = searching and (contains(category.label, query) or contains(category.id, query))
        local childRows = {}
        if category.groups then
            for g = 1, #category.groups do
                local group = category.groups[g]
                local groupMatch = searching and (contains(group.label, query) or contains(group.id, query))
                local itemRows = {}
                local anyItem = false
                for i = 1, #(group.items or {}) do
                    local item = group.items[i]
                    local itemMatch = searching and (contains(item.label, query) or contains(item.id, query))
                    if not searching or catMatch or groupMatch or itemMatch then
                        anyItem = true
                        push(itemRows, "item", item.id, item.label, 2,
                            Tree.itemAccepted(filter, tree, item.id) and Tree.ON or Tree.OFF, group.id)
                    end
                end
                if not searching or catMatch or groupMatch or anyItem then
                    push(childRows, "group", group.id, group.label, 1, Tree.mark(filter, tree, group.id), category.id)
                    if searching or expanded[group.id] then
                        for i = 1, #itemRows do
                            childRows[#childRows + 1] = itemRows[i]
                        end
                    end
                end
            end
        else
            for i = 1, #category.items do
                local item = category.items[i]
                local itemMatch = searching and (contains(item.label, query) or contains(item.id, query))
                if not searching or catMatch or itemMatch then
                    push(childRows, "item", item.id, item.label, 1,
                        Tree.itemAccepted(filter, tree, item.id) and Tree.ON or Tree.OFF, category.id)
                end
            end
        end
        if not searching or catMatch or #childRows > 0 then
            push(rows, "category", category.id, category.label, 0, Tree.mark(filter, tree, category.id), nil)
            if searching or expanded[category.id] then
                for i = 1, #childRows do
                    rows[#rows + 1] = childRows[i]
                end
            end
        end
    end
    return rows
end

local function labelFor(tree, fullType)
    local meta = tree and tree.byType and tree.byType[fullType]
    if meta and type(meta.label) == "string" and meta.label ~= "" then
        return meta.label
    end
    if type(fullType) == "string" then
        return fullType:match("([^%.]+)$") or fullType
    end
    return ""
end

local function countPhrase(label, count)
    if count == 1 then
        return label .. ": 1 item"
    end
    return label .. ": " .. tostring(count) .. " items"
end

local function acceptedIds(filter, tree, ids)
    local accepted = {}
    for i = 1, #ids do
        if Tree.itemAccepted(filter, tree, ids[i]) then
            accepted[#accepted + 1] = ids[i]
        end
    end
    return accepted
end

-- "Food: 12 items" when a whole category is ticked, "Hammer, Screws" when
-- only a few item types are. Nothing ticked is "No filter".
function Tree.summary(filter, tree)
    local Filter = PZSorter.Filter
    if not tree or type(tree.categories) ~= "table" then
        if Filter and Filter.summary then
            return Filter.summary(filter)
        end
        return "No filter"
    end
    local current = normalized(filter)
    local parts = {}
    local used = {}
    local loose = {}
    local function takeLoose(id)
        if used[id] then
            return
        end
        used[id] = true
        loose[#loose + 1] = labelFor(tree, id)
    end
    local categories = {}
    for i = 1, #tree.categories do
        categories[i] = tree.categories[i]
    end
    table.sort(categories, function(a, b)
        return tostring(a.label):lower() < tostring(b.label):lower()
    end)
    for c = 1, #categories do
        local category = categories[c]
        local ids = Tree.itemIds(tree, category.id)
        if current.categories[category.id] then
            local accepted = acceptedIds(current, tree, ids)
            if #ids == 0 then
                parts[#parts + 1] = category.label
            elseif #accepted > 0 then
                parts[#parts + 1] = countPhrase(category.label, #accepted)
            end
            for i = 1, #accepted do
                used[accepted[i]] = true
            end
        elseif category.groups then
            for g = 1, #category.groups do
                local group = category.groups[g]
                if current.categories[group.id] then
                    local gids = Tree.itemIds(tree, group.id)
                    local accepted = acceptedIds(current, tree, gids)
                    if group.id == Tree.FROZEN or #gids == 0 then
                        parts[#parts + 1] = group.label
                    elseif #accepted > 0 then
                        parts[#parts + 1] = countPhrase(group.label, #accepted)
                    end
                    for i = 1, #accepted do
                        used[accepted[i]] = true
                    end
                end
            end
            for i = 1, #ids do
                local id = ids[i]
                if not used[id] and Tree.itemAccepted(current, tree, id) then
                    takeLoose(id)
                end
            end
        else
            local accepted = acceptedIds(current, tree, ids)
            if #accepted > 4 then
                parts[#parts + 1] = countPhrase(category.label, #accepted)
                for i = 1, #accepted do
                    used[accepted[i]] = true
                end
            else
                for i = 1, #accepted do
                    takeLoose(accepted[i])
                end
            end
        end
    end
    for id, on in pairs(current.items) do
        if on and not used[id] and not current.excluded[id] then
            takeLoose(id)
        end
    end
    table.sort(loose)
    if #loose > 0 then
        if #loose <= 4 then
            parts[#parts + 1] = table.concat(loose, ", ")
        else
            parts[#parts + 1] = loose[1] .. ", " .. loose[2] .. ", " .. loose[3] .. " +" .. tostring(#loose - 3)
        end
    end
    if #parts == 0 then
        if Filter and Filter.NONE then
            return Filter.NONE
        end
        return "No filter"
    end
    return table.concat(parts, ", ")
end

function Tree.labels(tree)
    local map = {}
    local categories = tree and tree.categories or {}
    for c = 1, #categories do
        local category = categories[c]
        map[category.id] = category.label
        local groups = category.groups or {}
        for g = 1, #groups do
            map[groups[g].id] = groups[g].label
            for i = 1, #(groups[g].items or {}) do
                map[groups[g].items[i].id] = groups[g].items[i].label
            end
        end
        for i = 1, #category.items do
            map[category.items[i].id] = category.items[i].label
        end
    end
    return map
end

return Tree
