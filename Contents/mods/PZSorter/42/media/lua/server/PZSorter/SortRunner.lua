-- Move items out of a Sorter Crate. Server only.
--
-- The client plays the timed action and asks for the next step. This file
-- is the only place that takes an item out of one container and puts it in
-- another. A multiplayer client never loads this file, so it cannot create
-- a second copy by moving the item itself. Single player is the authority
-- too (isClient and isServer are both false there), and it runs these
-- functions directly.
--
-- SortPlan decides the order. Each step re-checks the live container, so a
-- container that was picked up, or that filled up, is skipped and the item
-- tries the next match. Cancelling drops the steps that have not run.
-- Items that already moved stay where they went.

require "PZSorter/Config"
require "PZSorter/Filter"
require "PZSorter/SortPlan"
require "PZSorter/Range"
require "PZSorter/Links"
require "PZSorter/WorldContainers"
require "PZSorter/Keys"
require "PZSorter/MoveGuard"

PZSorter = PZSorter or {}
PZSorter.SortRunner = PZSorter.SortRunner or {}

local Runner = PZSorter.SortRunner

if Runner._loaded then
    return Runner
end
Runner._loaded = true

local Config = PZSorter.Config
local Filter = PZSorter.Filter
local Plan = PZSorter.SortPlan
local Range = PZSorter.Range
local Links = PZSorter.Links
local World = PZSorter.WorldContainers
local Keys = PZSorter.Keys
local Guard = PZSorter.MoveGuard

-- One sort at a time per crate. The timed action's steps share this table.
-- Replacing it on a new SortBegin drops whatever the previous one had not
-- moved yet. It does not move those items back.
local sessions = {}

local function callMethod(object, method, ...)
    if not object or type(object[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[method], object, ...)
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
    if type(value) == "userdata" or type(value) == "table" then
        if type(value.toString) == "function" then
            local ok, text = pcall(value.toString, value)
            if ok and type(text) == "string" and text ~= "" then
                return text
            end
        end
        if value.name ~= nil then
            local name = asText(value.name)
            if name then
                return name
            end
        end
    end
    return nil
end

local function isA(value, className)
    if value == nil or not instanceof then
        return false
    end
    local ok, result = pcall(instanceof, value, className)
    return ok and result and true or false
end

local function playerKey(player)
    local id = callMethod(player, "getOnlineID")
    if id ~= nil and tostring(id) ~= "-1" then
        return "id:" .. tostring(id)
    end
    local name = asText(callMethod(player, "getUsername"))
    if name then
        return "name:" .. name
    end
    return "local"
end

local function squareAt(x, y, z)
    local cell = getCell and getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end
    return cell:getGridSquare(x, y, z)
end

local function sorterPosition(object, record)
    local square = object and object.getSquare and object:getSquare()
    if square and square.getX then
        return { x = square:getX(), y = square:getY(), z = square:getZ() }
    end
    return {
        x = record and record.x or 0,
        y = record and record.y or 0,
        z = record and record.z or 0,
    }
end

-- Keys stay in the crate. Keys.isKey never calls hasTag with a string.
local function isKey(item)
    return Keys.isKey(item)
end

local function isFavorite(item)
    local favorite = callMethod(item, "isFavorite")
    if favorite == nil then
        favorite = callMethod(item, "isFavourite")
    end
    return favorite and true or false
end

local function isEquipped(item, player)
    if callMethod(item, "isEquipped") then
        return true
    end
    if callMethod(item, "isWorn") then
        return true
    end
    if not player then
        return false
    end
    if callMethod(player, "getPrimaryHandItem") == item then
        return true
    end
    if callMethod(player, "getSecondaryHandItem") == item then
        return true
    end
    return false
end

local function isBag(item)
    if isA(item, "InventoryContainer") then
        return true
    end
    local display = asText(callMethod(item, "getDisplayCategory"))
    if display == "Bag" or display == "Container" then
        local inventory = callMethod(item, "getInventory")
        if inventory then
            return true
        end
    end
    return false
end

local function fullTypeOf(item)
    local full = asText(callMethod(item, "getFullType"))
    if full then
        return full
    end
    local typeName = asText(callMethod(item, "getType"))
    local moduleName = asText(callMethod(item, "getModule"))
    if moduleName and typeName then
        return moduleName .. "." .. typeName
    end
    return typeName or "item"
end

local function displayCategoryOf(item)
    return asText(callMethod(item, "getDisplayCategory"))
end

local function containsItem(container, item)
    if not container or not item or type(container.getItems) ~= "function" then
        return false
    end
    local items = callMethod(container, "getItems")
    if not items or not items.size or not items.get then
        return false
    end
    local wanted = callMethod(item, "getID")
    for i = 0, items:size() - 1 do
        local found = items:get(i)
        if found == item then
            return true
        end
        if wanted ~= nil and callMethod(found, "getID") == wanted then
            return true
        end
    end
    return false
end

local function capacityOf(container, player, weight, capacity)
    if player and type(container.getEffectiveCapacity) == "function" then
        local value = callMethod(container, "getEffectiveCapacity", player)
        if type(value) == "number" and value > 0 then
            return value
        end
    end
    return capacity
end

-- The game's own room check when it is there. Otherwise the same weight
-- comparison SortPlan uses, so a container that is over its capacity is
-- not given another item.
local function roomFor(container, item, player)
    if not container or not item then
        return false
    end
    if type(container.hasRoomFor) == "function" then
        local ok, room = pcall(container.hasRoomFor, container, player, item)
        if ok then
            return room and true or false
        end
        print("PZSorter: sort room check failed: " .. tostring(room))
    end
    local weight, capacity = World.weightAndCapacity(container)
    capacity = capacityOf(container, player, weight, capacity)
    if capacity <= 0 then
        return false
    end
    return weight + World.itemWeight(item) <= capacity + 0.0001
end

-- Local remove-then-add, and only then the multiplayer packet. Doing the
-- add on the client as well is what duplicates items, so this function is
-- not called from the client file.
-- Room and "not the floor" are checked again here, after the plan, and
-- before the item is taken out of the sorter. A failed add is put back
-- in the sorter. Nothing in this function drops an item on the ground.
local function transfer(src, dest, item, player)
    local kind = asText(callMethod(dest, "getType"))
    local facts = {
        type = kind,
        floor = kind == "floor",
        sameAsSource = dest ~= nil and dest == src,
        addable = dest ~= nil and type(dest.AddItem) == "function",
        room = false,
    }
    if not facts.floor and facts.addable and not facts.sameAsSource then
        facts.room = roomFor(dest, item, player)
    end
    local allowed, reason = Guard.allow(facts)
    if not allowed then
        return false, reason
    end
    if not containsItem(src, item) then
        return false, "gone"
    end
    if containsItem(dest, item) then
        return false, "already there"
    end
    local removed = false
    if type(src.DoRemoveItem) == "function" then
        local ok, err = pcall(src.DoRemoveItem, src, item)
        removed = ok
        if not ok then
            print("PZSorter: sort remove failed: " .. tostring(err))
        end
    elseif type(src.Remove) == "function" then
        local ok, err = pcall(src.Remove, src, item)
        removed = ok
        if not ok then
            print("PZSorter: sort remove failed: " .. tostring(err))
        end
    end
    if not removed or containsItem(src, item) then
        return false, "remove failed"
    end
    if type(dest.AddItem) ~= "function" then
        if type(src.AddItem) == "function" then
            pcall(src.AddItem, src, item)
        end
        return false, "no add"
    end
    local added, addErr = pcall(dest.AddItem, dest, item)
    if Guard.afterRemove(added) == "restore" then
        print("PZSorter: sort add failed: " .. tostring(addErr))
        if type(src.AddItem) == "function" then
            pcall(src.AddItem, src, item)
        end
        if not containsItem(src, item) then
            print("PZSorter: sort restore failed, item was not put on the floor " .. tostring(fullTypeOf(item)))
        end
        return false, "full"
    end
    if type(item.setContainer) == "function" then
        local current = callMethod(item, "getContainer")
        if current ~= dest then
            pcall(item.setContainer, item, dest)
        end
    end
    if isServer and isServer() then
        if sendRemoveItemFromContainer then
            pcall(sendRemoveItemFromContainer, src, item)
        end
        if sendAddItemToContainer then
            pcall(sendAddItemToContainer, dest, item)
        end
    end
    pcall(function()
        if src.setDrawDirty then
            src:setDrawDirty(true)
        end
        if dest.setDrawDirty then
            dest:setDrawDirty(true)
        end
    end)
    return true
end

local function liveDestination(entry, origin)
    if type(entry) ~= "table" then
        return nil, "missing"
    end
    local square = squareAt(entry.x, entry.y, entry.z)
    if not square then
        return nil, "unloaded"
    end
    local row = World.find(square, entry.index)
    if not row or not row.container then
        return nil, "missing"
    end
    local status = Links.status(origin, entry, Range.current(), true, true)
    if status ~= "ok" then
        return nil, status
    end
    return row.container, "ok"
end

local function collectItems(src, player)
    local facts = {}
    local javaById = {}
    local totalWeight = 0
    if not src or type(src.getItems) ~= "function" then
        return facts, javaById, totalWeight
    end
    local items = callMethod(src, "getItems")
    if not items or not items.size or not items.get then
        return facts, javaById, totalWeight
    end
    -- Direct children only. A bag is one of those children. Its own
    -- inventory is not walked, so the bag moves whole.
    for i = 0, items:size() - 1 do
        local javaItem = items:get(i)
        if javaItem then
            local weight = World.itemWeight(javaItem)
            totalWeight = totalWeight + weight
            local id = callMethod(javaItem, "getID")
            if id == nil then
                id = "index-" .. tostring(i)
            end
            id = tostring(id)
            local full = fullTypeOf(javaItem)
            local foodFacts = {}
            if PZSorter.FilterTree and PZSorter.FilterTree.factsFromObject then
                local readOk, read = pcall(PZSorter.FilterTree.factsFromObject, javaItem)
                if readOk and type(read) == "table" then
                    foodFacts = read
                else
                    print("PZSorter: sort food facts failed: " .. tostring(read))
                end
            end
            local fact = {
                id = id,
                category = displayCategoryOf(javaItem),
                type = full,
                weight = weight,
                equipped = isEquipped(javaItem, player),
                favorited = isFavorite(javaItem),
                key = isKey(javaItem),
                bag = isBag(javaItem),
                food = foodFacts.food and true or false,
                canRot = foodFacts.canRot and true or false,
                frozen = foodFacts.frozen and true or false,
            }
            facts[#facts + 1] = fact
            javaById[id] = javaItem
            local flags = ""
            if fact.equipped then
                flags = flags .. " equipped"
            end
            if fact.favorited then
                flags = flags .. " favorited"
            end
            if fact.key then
                flags = flags .. " key"
            end
            if fact.bag then
                flags = flags .. " bag"
            end
            local group = "none"
            if fact.food and PZSorter.FilterTree and PZSorter.FilterTree.foodGroup then
                group = PZSorter.FilterTree.foodGroup(fact) or "none"
            end
            print("PZSorter: sort item " .. full
                .. " category=" .. tostring(fact.category)
                .. " group=" .. tostring(group)
                .. " weight=" .. string.format("%.2f", weight)
                .. flags)
        end
    end
    return facts, javaById, totalWeight
end

local function linkId(link)
    return tostring(link.x) .. ":" .. tostring(link.y) .. ":" .. tostring(link.z) .. ":" .. tostring(link.index)
end

local function collectContainers(record, origin, player)
    local plain = {}
    local lookup = {}
    local links = Links.each(record and record.links)
    for i = 1, #links do
        local link = links[i]
        local id = linkId(link)
        local square = squareAt(link.x, link.y, link.z)
        local status = "unloaded"
        local weight = 0
        local capacity = 0
        local row = nil
        if not square then
            status = "unloaded"
        else
            row = World.find(square, link.index)
            if not row or not row.container then
                status = "missing"
            else
                status = Links.status(origin, link, Range.current(), true, true)
                weight, capacity = World.weightAndCapacity(row.container)
                capacity = capacityOf(row.container, player, weight, capacity)
            end
        end
        local shown = World.containerLabel(link.name, row and row.container)
        local summary = Filter.summary(link.filter)
        if PZSorter.FilterTree and PZSorter.FilterTree.summary and PZSorter.FilterTree.cached then
            local summaryOk, text = pcall(function()
                return PZSorter.FilterTree.summary(link.filter, PZSorter.FilterTree.cached())
            end)
            if summaryOk and type(text) == "string" then
                summary = text
            end
        end
        print("PZSorter: sort container " .. tostring(shown)
            .. " status=" .. status
            .. " priority=" .. tostring(Links.clampPriority(link.priority))
            .. " filter=" .. summary
            .. " weight=" .. tostring(weight) .. "/" .. tostring(capacity))
        if status ~= "ok" then
            print("PZSorter: sort skip " .. tostring(shown) .. " status=" .. status)
        end
        plain[#plain + 1] = {
            id = id,
            name = shown,
            x = link.x,
            y = link.y,
            z = link.z,
            priority = link.priority,
            filter = link.filter,
            weight = weight,
            capacity = capacity,
            inRange = status ~= "range" and status ~= "unloaded",
            missing = status == "missing" or status == "unloaded",
        }
        lookup[id] = {
            id = id,
            name = shown,
            x = link.x,
            y = link.y,
            z = link.z,
            index = link.index,
        }
    end
    return plain, lookup
end

local function deliver(player, summary)
    if type(summary) ~= "string" then
        summary = Plan.summary(nil)
    end
    print("PZSorter: sort summary " .. summary)
    -- The player who sorted is this process in single player and on a
    -- listen server, so the popup can open from the return value. A
    -- dedicated server has no popup; it sends the sentence to that player.
    if Config.onPlayer() then
        return { ok = true, summary = summary }
    end
    if sendServerCommand and player then
        pcall(function()
            sendServerCommand(player, Config.COMMAND_MODULE, "SortSummary", { text = summary })
        end)
    end
    return { ok = true, summary = summary }
end

local function sessionFor(player, sorterId, verb)
    local session = sessions[tostring(sorterId)]
    if not session then
        print("PZSorter: sort " .. verb .. " with no session")
        return nil
    end
    if session.playerKey ~= playerKey(player) then
        print("PZSorter: sort " .. verb .. " ignored, different player")
        return nil
    end
    return session
end

local function commit(session, player)
    local step = session.ops[session.index]
    if not step then
        return false
    end
    session.index = session.index + 1
    local typeName = step.typeName or "item"
    if step.reason == "equipped" or step.reason == "favorited" or step.reason == "key" then
        session.leftovers[#session.leftovers + 1] = { reason = step.reason }
        print("PZSorter: sort leave " .. typeName .. " reason=" .. step.reason)
        return true
    end
    local item = step.item
    if isEquipped(item, player) then
        session.leftovers[#session.leftovers + 1] = { reason = "equipped" }
        print("PZSorter: sort leave " .. typeName .. " reason=equipped")
        return true
    end
    if isFavorite(item) then
        session.leftovers[#session.leftovers + 1] = { reason = "favorited" }
        print("PZSorter: sort leave " .. typeName .. " reason=favorited")
        return true
    end
    if isKey(item) then
        session.leftovers[#session.leftovers + 1] = { reason = "key" }
        print("PZSorter: sort leave " .. typeName .. " reason=key")
        return true
    end
    if not containsItem(session.src, item) then
        print("PZSorter: sort item gone " .. typeName)
        return true
    end
    local ranked = step.ranked or {}
    local fullName = step.containerName
    local sawFull = false
    local sawFloor = false
    for i = 1, #ranked do
        local rankedId = tostring(ranked[i].id)
        local entry = session.lookup[rankedId]
        local name = (entry and entry.name) or ranked[i].name
        if not entry then
            print("PZSorter: sort skip " .. tostring(name) .. " status=missing")
        else
            local dest, status = liveDestination(entry, session.origin)
            if not dest then
                print("PZSorter: sort skip " .. tostring(entry.name) .. " status=" .. tostring(status))
            elseif not roomFor(dest, item, player) then
                sawFull = true
                if not fullName then
                    fullName = entry.name
                end
            else
                local moved, why = transfer(session.src, dest, item, player)
                if moved then
                    session.moves[#session.moves + 1] = { containerName = entry.name }
                    print("PZSorter: sort move " .. typeName .. " -> " .. tostring(entry.name))
                    return true
                end
                print("PZSorter: sort move failed " .. typeName .. " -> " .. tostring(entry.name) .. " (" .. tostring(why) .. ")")
                if why == "floor" then
                    sawFloor = true
                else
                    sawFull = true
                    if not fullName then
                        fullName = entry.name
                    end
                end
            end
        end
    end
    if sawFull then
        session.leftovers[#session.leftovers + 1] = { reason = "full", containerName = fullName }
        print("PZSorter: sort leave " .. typeName .. " reason=full container=" .. tostring(fullName))
    elseif sawFloor then
        session.leftovers[#session.leftovers + 1] = { reason = "floor" }
        print("PZSorter: sort leave " .. typeName .. " reason=floor")
    else
        session.leftovers[#session.leftovers + 1] = { reason = "no_match" }
        print("PZSorter: sort leave " .. typeName .. " reason=no_match")
    end
    return true
end

local function summarize(session, player, cancelled)
    session.finished = true
    session.summary = Plan.summary({
        moves = session.moves,
        leftovers = session.leftovers,
    })
    if cancelled then
        print("PZSorter: sort cancelled " .. session.summary)
    else
        print("PZSorter: sort finished " .. session.summary)
    end
    return deliver(player, session.summary)
end

function Runner.begin(player, object, record)
    if type(record) ~= "table" or record.id == nil then
        print("PZSorter: sort refused, sorter has no id")
        return false
    end
    local src = object and object.getContainer and object:getContainer()
    if not src then
        print("PZSorter: sort refused, crate has no container")
        return false
    end
    local key = tostring(record.id)
    if sessions[key] and not sessions[key].finished then
        print("PZSorter: sort replaced an unfinished session on " .. tostring(record.name))
    end
    local origin = sorterPosition(object, record)
    local facts, javaById, totalWeight = collectItems(src, player)
    local plain, lookup = collectContainers(record, origin, player)
    local built = Plan.build({
        sorter = origin,
        items = facts,
        containers = plain,
    })
    local typeById = {}
    for i = 1, #facts do
        typeById[tostring(facts[i].id)] = facts[i].type
    end
    local ops = {}
    for i = 1, #built.steps do
        local step = built.steps[i]
        local itemId = tostring(step.itemId)
        ops[#ops + 1] = {
            action = step.action,
            reason = step.reason,
            containerName = step.containerName,
            typeName = typeById[itemId] or itemId,
            item = javaById[itemId],
            ranked = step.ranked or {},
        }
    end
    local speed = Plan.currentSpeed()
    sessions[key] = {
        playerKey = playerKey(player),
        sorterId = key,
        src = src,
        origin = origin,
        lookup = lookup,
        ops = ops,
        index = 1,
        moves = {},
        leftovers = {},
        finished = false,
        summary = nil,
    }
    print("PZSorter: sort begin name=" .. tostring(record.name)
        .. " items=" .. tostring(#facts)
        .. " weight=" .. string.format("%.2f", totalWeight)
        .. " speed=" .. speed
        .. " steps=" .. tostring(#ops))
    return { ok = true, steps = #ops, speed = speed }
end

function Runner.step(player, sorterId)
    local session = sessionFor(player, sorterId, "step")
    if not session or session.finished then
        return nil
    end
    if session.index > #session.ops then
        return { ok = true, done = true }
    end
    local ok, err = pcall(commit, session, player)
    if not ok then
        print("PZSorter: sort step failed: " .. tostring(err))
        return nil
    end
    return { ok = true }
end

function Runner.finish(player, sorterId)
    local session = sessionFor(player, sorterId, "finish")
    if not session then
        return deliver(player, Plan.summary(nil))
    end
    if session.finished then
        return deliver(player, session.summary)
    end
    while session.index <= #session.ops do
        local ok, err = pcall(commit, session, player)
        if not ok then
            print("PZSorter: sort finish failed: " .. tostring(err))
            break
        end
    end
    return summarize(session, player, false)
end

function Runner.cancel(player, sorterId)
    local session = sessionFor(player, sorterId, "cancel")
    if not session then
        return deliver(player, Plan.summary(nil))
    end
    if session.finished then
        return deliver(player, session.summary)
    end
    return summarize(session, player, true)
end

print("PZSorter: sort runner loaded (0.4.0)")

return Runner
