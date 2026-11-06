-- Server-side record of every Sorter Crate.
--
-- Two copies are kept, and they are written together:
--   * On the crate itself (the object's mod data). This is the spec's save:
--     name, unique id, an empty link list, and schema = 1. It travels with
--     the square, so a save, quit, and reload still has it.
--   * A world list under the same mod-data name. That list is how the next
--     crate knows to suggest "Sorter 2" without walking the whole map, and
--     it is what we remove from when the crate is dismantled.
--
-- This file is authoritative. The name box asks; the server decides. Item
-- moves for a later step will do the same, which is why dismantle already
-- goes through a client command even in single player.

require "PZSorter/Config"
require "PZSorter/Names"
require "PZSorter/Dismantle"
require "PZSorter/ItemTags"
require "PZSorter/Carry"

PZSorter = PZSorter or {}
PZSorter.SorterData = PZSorter.SorterData or {}

local Data = PZSorter.SorterData
local Config = PZSorter.Config

-- The game loads every server file. Guard the event hooks so a double load
-- cannot register them twice and run every command twice.
if Data._hooked then
    return Data
end
Data._hooked = true

local function worldTable()
    -- getOrCreate returns the same table every time, and the game writes it
    -- into the save. Replacing the table would orphan the saved one, so we
    -- only add fields to the table we were given.
    local stored = ModData.getOrCreate(Config.MOD_DATA_KEY)
    if stored.schema == nil then
        stored.schema = Config.SCHEMA
    end
    if stored.nextId == nil then
        stored.nextId = 1
    end
    if stored.sorters == nil then
        stored.sorters = {}
    end
    return stored
end

function Data.getWorld()
    return worldTable()
end

local function syncWorld()
    -- getOrCreate's table is the one the save writes. In single player
    -- isServer() is false, and ModData.transmit can replace that table
    -- with an empty one. The next crate then suggests "Sorter 1" again
    -- even though the placed crates still have their names.
    -- A real server still transmits so co-op clients share one list.
    if isServer and isServer() and ModData.transmit then
        pcall(function()
            ModData.transmit(Config.MOD_DATA_KEY)
        end)
    end
end

local function spriteNameOf(object)
    if not object or not object.getSprite then
        return nil
    end
    local sprite = object:getSprite()
    if not sprite or not sprite.getName then
        return nil
    end
    return sprite:getName()
end

function Data.isSorterObject(object)
    return Config.isSorterSpriteName(spriteNameOf(object))
end

local function namedCrateCount(records)
    local count = 0
    if type(records) ~= "table" then
        return 0
    end
    for _, record in pairs(records) do
        if type(record) == "table" and not record.gone and type(record.name) == "string" then
            count = count + 1
        end
    end
    return count
end

-- First time we see a crate that has no record yet. The suggested name is
-- stored immediately, before the player types, so a second crate placed
-- while the first box is still open does not also get "Sorter 1".
function Data.initNew(object)
    local square = object:getSquare()
    if not square then
        return nil
    end
    -- A picked-up crate is being placed. Keep its id and links. A new id
    -- here would orphan every container that still points at the old one,
    -- and the name box would open for a crate the player already named.
    local pending = PZSorter.Carry and PZSorter.Carry.pending
    if type(pending) == "table" and pending.id ~= nil then
        PZSorter.Carry.pending = nil
        local record = PZSorter.Carry.restore(pending, square:getX(), square:getY(), square:getZ())
        object:getModData()[Config.MOD_DATA_KEY] = record
        local world = worldTable()
        PZSorter.Names.absorb(world.sorters, record)
        local numericId = tonumber(record.id)
        if numericId and world.nextId <= numericId then
            world.nextId = numericId + 1
        end
        syncWorld()
        Data.applyContainerName(object)
        if object.transmitModData then
            pcall(function()
                object:transmitModData()
            end)
        end
        print("PZSorter: place restored name=" .. tostring(record.name) .. " links=" .. tostring(#record.links))
        return record
    end
    local world = worldTable()
    local id = tostring(world.nextId)
    world.nextId = world.nextId + 1
    local alreadyNamed = namedCrateCount(world.sorters)
    local name = PZSorter.Names.nextFromRecords(world.sorters)
    print("PZSorter: next name " .. name .. " with " .. tostring(alreadyNamed) .. " crates already named")
    local record = {
        schema = Config.SCHEMA,
        id = id,
        name = name,
        nameConfirmed = false,
        -- Links are step 2. The field is here so a later step does not have
        -- to invent a second save shape for crates built in this version.
        links = {},
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
    }
    -- appliedName is the last name we wrote onto the container. It starts
    -- as the suggestion, so a name the player types next is not mistaken
    -- for a vanilla rename of this automatic one.
    record.appliedName = name
    object:getModData()[Config.MOD_DATA_KEY] = record
    PZSorter.Names.absorb(world.sorters, record)
    syncWorld()
    if object.transmitModData then
        -- The build action sends the object on its own. transmitModData only
        -- sends the record, which is what the name box on the other side of
        -- a co-op game has to read. It is not transmitCompleteItemToClients,
        -- which would duplicate the crate.
        pcall(function()
            object:transmitModData()
        end)
    end
    return record
end

-- A crate that was loaded from a save already has a record. Make sure the
-- world list still points at it, in case that list was lost and the crate
-- was not. Never overwrite a name the player already confirmed.
function Data.remember(object)
    local record = object:getModData()[Config.MOD_DATA_KEY]
    if type(record) ~= "table" or record.id == nil then
        return
    end
    local square = object:getSquare()
    if square then
        record.x = square:getX()
        record.y = square:getY()
        record.z = square:getZ()
    end
    if record.links == nil then
        record.links = {}
    end
    local world = worldTable()
    local id = tostring(record.id)
    local previous = world.sorters[id]
    PZSorter.Names.absorb(world.sorters, record)
    local updated = world.sorters[id]
    local changed = type(previous) ~= "table"
        or type(updated) ~= "table"
        or previous.name ~= updated.name
        or previous.x ~= updated.x
        or previous.y ~= updated.y
        or previous.z ~= updated.z
        or previous.nameConfirmed ~= updated.nameConfirmed
        or previous.gone ~= updated.gone
    -- Ids are handed out from nextId. A loaded crate must not make the next
    -- new crate reuse an id that is already on the map.
    local numericId = tonumber(record.id)
    if numericId and world.nextId <= numericId then
        world.nextId = numericId + 1
        changed = true
    end
    if changed then
        syncWorld()
    end
end

-- The tile definition is what gives the crate its 50 capacity after a
-- reload (the chunk loader reads ContainerCapacity). A crate that was just
-- built may not have been through that loader yet, so we attach a container
-- once, and only when it does not already have one. Replacing an existing
-- container would throw away whatever the player had put inside.
function Data.ensureContainer(object)
    if not object.getContainer or not object.setContainer then
        return
    end
    if object:getContainer() then
        return
    end
    if not ItemContainer or not ItemContainer.new then
        return
    end
    local container = ItemContainer.new()
    if container.setType then
        container:setType("crate")
    end
    if container.setCapacity then
        container:setCapacity(Config.CAPACITY)
    end
    object:setContainer(container)
end

function Data.onObjectAdded(object)
    if not Data.isSorterObject(object) then
        return
    end
    local existing = object:getModData()[Config.MOD_DATA_KEY]
    if type(existing) ~= "table" or existing.id == nil then
        Data.initNew(object)
        Data.ensureContainer(object)
    else
        Data.remember(object)
    end
end

local function findOnSquare(x, y, z, id)
    local cell = getCell()
    if not cell then
        return nil
    end
    local square = cell:getGridSquare(x, y, z)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Data.isSorterObject(object) then
            local record = object:getModData()[Config.MOD_DATA_KEY]
            if id == nil or (record and tostring(record.id) == tostring(id)) then
                return object
            end
        end
    end
    return nil
end

local function playerSquareDistance(player, object)
    if not player or not player.getSquare or not object.getSquare then
        return nil
    end
    local playerSquare = player:getSquare()
    local objectSquare = object:getSquare()
    if not playerSquare or not objectSquare then
        return nil
    end
    if playerSquare:getZ() ~= objectSquare:getZ() then
        return nil
    end
    local dx = math.abs(playerSquare:getX() - objectSquare:getX())
    local dy = math.abs(playerSquare:getY() - objectSquare:getY())
    return math.max(dx, dy)
end

function Data.setName(player, args)
    print("PZSorter: setName entered")
    if type(args) ~= "table" then
        return
    end
    local object = findOnSquare(args.x, args.y, args.z, args.id)
    if not object then
        return
    end
    -- Standing at the crate is enough. The range sandbox option is about
    -- assigned containers, not about who may rename the crate they just built.
    local distance = playerSquareDistance(player, object)
    if distance == nil or distance > 3 then
        return
    end
    local name, reason = PZSorter.Names.validate(args.name)
    if not name then
        if player and sendServerCommand then
            sendServerCommand(player, Config.COMMAND_MODULE, "NameRejected", {
                id = args.id,
                x = args.x,
                y = args.y,
                z = args.z,
                reason = reason,
            })
        end
        return
    end
    local record = object:getModData()[Config.MOD_DATA_KEY]
    if type(record) ~= "table" then
        Data.onObjectAdded(object)
        record = object:getModData()[Config.MOD_DATA_KEY]
    end
    if type(record) ~= "table" then
        return
    end
    record.name = name
    record.nameConfirmed = true
    local world = worldTable()
    PZSorter.Names.absorb(world.sorters, record)
    syncWorld()
    Data.applyContainerName(object)
    if object.transmitModData then
        pcall(function()
            object:transmitModData()
        end)
    end
end

local function tagsInInventory(player)
    local inventory = player and player.getInventory and player:getInventory()
    local ok, found = pcall(function()
        return PZSorter.ItemTags.held(inventory)
    end)
    if not ok then
        print("PZSorter: tool check failed: " .. tostring(found))
        return {}
    end
    return found or {}
end

-- The loot window reads container:getCustomName() (ISInventoryPage, the
-- world-object loop). The container type "crate" would otherwise title
-- itself "Crate".
function Data.applyContainerName(object)
    if not object or not object.getContainer then
        return
    end
    local record = object.getModData and object:getModData()[Config.MOD_DATA_KEY]
    local title = PZSorter.Names.containerTitle(record and record.name)
    local container = object:getContainer()
    -- ItemContainer:setCustomName takes the title string. That is what the
    -- loot window reads back with getCustomName. An InventoryItem uses
    -- setName plus setCustomName(true) instead, and must not be called here.
    local wrote = false
    if container and type(container.setCustomName) == "function" and type(title) == "string" then
        container:setCustomName(title)
        wrote = true
    end
    -- Remember the write only when the container actually took it. If the
    -- write did not happen, the previous appliedName is still the name a
    -- refresh should ignore, not treat as a vanilla rename.
    if wrote and type(record) == "table" then
        record.appliedName = title
    end
end

-- SpriteConfig.OnCreate. Runs when the build menu finishes the crate,
-- including when Build cheat skips the material check.
function Data.onBuilt(object, character)
    print("PZSorter: onBuilt entered authority=" .. tostring(Config.onAuthority()))
    if not Config.onAuthority() then
        print("PZSorter: onBuilt skipped, this side does not save")
        return
    end
    Data.onObjectAdded(object)
    Data.applyContainerName(object)
    local record = object.getModData and object:getModData()[Config.MOD_DATA_KEY]
    if type(record) == "table" then
        print("PZSorter: name assigned " .. tostring(record.name) .. " id=" .. tostring(record.id))
    else
        print("PZSorter: onBuilt stored no record")
        return
    end
    if record.nameConfirmed then
        print("PZSorter: name already confirmed, no prompt")
        return
    end
    -- Single player has no client/server split, and sendServerCommand is
    -- delivered in-process. Opening the box and also sending OpenName
    -- shows the box twice. The player side opens it here and stops.
    if Config.onPlayer() then
        if PZSorter.NamePrompt and PZSorter.NamePrompt.onBuilt then
            print("PZSorter: opening name box directly")
            PZSorter.NamePrompt.onBuilt(object, character)
        else
            print("PZSorter: name prompt is not loaded")
        end
        print("PZSorter: not sending OpenName on the player side")
        return
    end
    if not character or not sendServerCommand then
        print("PZSorter: no character or sendServerCommand, direct open only")
        return
    end
    local square = object.getSquare and object:getSquare()
    if not square then
        print("PZSorter: onBuilt object has no square")
        return
    end
    print("PZSorter: command sent OpenName")
    sendServerCommand(character, Config.COMMAND_MODULE, "OpenName", {
        id = record.id,
        name = record.name,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
    })
end

local function carpentryLevel(player)
    if not player or not player.getPerkLevel or not Perks then
        return 0
    end
    local perk = Perks.Woodwork
    if not perk then
        return 0
    end
    return player:getPerkLevel(perk) or 0
end

-- ZombRand(n) returns 0 .. n-1. The roll function wants 1 .. 100.
local function gameRoll()
    if ZombRand then
        return ZombRand(100) + 1
    end
    -- Only used if the random binding is missing. Still 1..100.
    return math.floor(math.random() * 100) + 1
end

local function spillContents(object, square)
    if not object.getContainer or not square or not square.AddWorldInventoryItem then
        return
    end
    local container = object:getContainer()
    if not container or not container.getItems then
        return
    end
    local items = container:getItems()
    if not items or not items.size then
        return
    end
    -- Walk backwards. Removing an item shifts the Java list under us.
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if container.Remove then
            container:Remove(item)
        elseif container.DoRemoveItem then
            container:DoRemoveItem(item)
        end
        local ox = 0.4
        local oy = 0.4
        if ZombRandFloat then
            ox = ZombRandFloat(0.2, 0.8)
            oy = ZombRandFloat(0.2, 0.8)
        end
        square:AddWorldInventoryItem(item, ox, oy, 0)
    end
end

local function give(player, fullType, count)
    if count <= 0 then
        return
    end
    local inventory = player and player.getInventory and player:getInventory()
    if not inventory or not inventory.AddItem then
        return
    end
    for _ = 1, count do
        -- AddItem returns the new item. Vanilla scrap goes into the
        -- inventory (it can over-encumber you), not onto the ground.
        inventory:AddItem(fullType)
    end
end

local function removeObject(object)
    local square = object:getSquare()
    if not square then
        return
    end
    -- Tell other clients first, then drop it from this square. Doing only
    -- the local remove leaves a ghost crate in co-op.
    if square.transmitRemoveItemFromSquare then
        pcall(function()
            square:transmitRemoveItemFromSquare(object)
        end)
    end
    if square.RemoveTileObject then
        pcall(function()
            square:RemoveTileObject(object)
        end)
    end
    if object.removeFromSquare then
        pcall(function()
            object:removeFromSquare()
        end)
    end
end

function Data.dismantleObject(player, object)
    print("PZSorter: dismantle running")
    if not object then
        print("PZSorter: dismantle has no crate")
        return false
    end
    local distance = playerSquareDistance(player, object)
    print("PZSorter: dismantle distance=" .. tostring(distance))
    if distance == nil or distance > 2 then
        print("PZSorter: dismantle stopped, player is not next to the crate")
        return false
    end
    local tags = tagsInInventory(player)
    print("PZSorter: dismantle tools=" .. table.concat(tags, ","))
    if not PZSorter.Dismantle.hasRequiredTools(tags) then
        print("PZSorter: dismantle stopped, need a hammer and a saw")
        if player and player.setHaloNote then
            player:setHaloNote(getText("IGUI_PZSorter_DismantleNeedTools"))
        end
        return false
    end
    local result = PZSorter.Dismantle.returns(carpentryLevel(player), gameRoll)
    local square = object:getSquare()
    local spilled, spillError = pcall(function()
        spillContents(object, square)
    end)
    if not spilled then
        print("PZSorter: could not spill crate contents: " .. tostring(spillError))
    end
    local items = Config.ITEMS
    give(player, items.plank, result.planks)
    give(player, items.screws, result.screws)
    give(player, items.smallMetalSheet, result.smallMetalSheets)
    print("PZSorter: gave materials planks=" .. tostring(result.planks) .. " screws=" .. tostring(result.screws) .. " sheet=" .. tostring(result.smallMetalSheets))
    local record = object:getModData()[Config.MOD_DATA_KEY]
    if record and PZSorter.Commands and PZSorter.Commands.releaseSorter then
        print("PZSorter: clearing links before the crate is removed")
        PZSorter.Commands.releaseSorter(record)
    end
    print("PZSorter: removing crate")
    removeObject(object)
    if record and record.id ~= nil then
        local world = worldTable()
        PZSorter.Names.absorb(world.sorters, { gone = true, id = record.id })
        syncWorld()
    end
    print("PZSorter: dismantle finished")
    return true
end

local function commandDismantle(player, args)
    print("PZSorter: dismantle command")
    if type(args) ~= "table" then
        print("PZSorter: dismantle command had no arguments")
        return
    end
    local object = findOnSquare(args.x, args.y, args.z, args.id)
    if not object then
        print("PZSorter: dismantle command found no crate at " .. tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z))
        return
    end
    Data.dismantleObject(player, object)
end

local COMMANDS = {
    SetName = Data.setName,
    Dismantle = commandDismantle,
}

local function onClientCommand(module, command, player, args)
    if module ~= Config.COMMAND_MODULE then
        return
    end
    print("PZSorter: OnClientCommand " .. tostring(command) .. " authority=" .. tostring(Config.onAuthority()))
    if not Config.onAuthority() then
        print("PZSorter: OnClientCommand skipped, this side does not save")
        return
    end
    local handler = COMMANDS[command]
    if handler then
        handler(player, args)
    elseif command ~= "Assign" and command ~= "Move" and command ~= "Unassign" then
        -- Those three are handled in Commands.lua, which has its own listener.
        print("PZSorter: OnClientCommand has no handler for " .. tostring(command))
    end
end

local function onObjectAdded(object)
    if not Config.onAuthority() then
        return
    end
    Data.onObjectAdded(object)
end

-- Chunk load does not always fire OnObjectAdded for objects that were
-- already in the save. LoadGridsquare does fire, and that is what brings
-- the names back after a quit.
local function onLoadGridsquare(square)
    if not Config.onAuthority() then
        return
    end
    if not square or not square.getObjects then
        return
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        Data.onObjectAdded(objects:get(i))
    end
end

Events.OnObjectAdded.Add(onObjectAdded)
Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnClientCommand.Add(onClientCommand)

print("PZSorter: crate save data loaded (0.2.0)")

return Data
