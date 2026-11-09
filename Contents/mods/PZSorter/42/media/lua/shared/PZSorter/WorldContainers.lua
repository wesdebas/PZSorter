-- Containers sitting on a tile, and the few facts the link rules need.
--
-- A fridge/freezer combo is one object with two containers. A counter next
-- to it is a second object. The index stored on a link is the position in
-- this list, starting at 0, walking the tile's objects from first to last.
-- That is the "index on the tile". The index inside one object is kept
-- only so the sorter id can be written on that object's save data.

PZSorter = PZSorter or {}
PZSorter.WorldContainers = PZSorter.WorldContainers or {}

local World = PZSorter.WorldContainers

require "PZSorter/Config"

local Config = PZSorter.Config

local function spriteNameOf(object)
    if not object or not object.getSprite then
        return nil
    end
    local ok, sprite = pcall(function()
        return object:getSprite()
    end)
    if not ok or not sprite or not sprite.getName then
        return nil
    end
    local named, name = pcall(function()
        return sprite:getName()
    end)
    if named then
        return name
    end
    return nil
end

local function containerCount(object)
    if object.getContainerCount then
        local ok, count = pcall(function()
            return object:getContainerCount()
        end)
        if ok and type(count) == "number" and count > 0 then
            return count
        end
    end
    if object.getContainer then
        local ok, container = pcall(function()
            return object:getContainer()
        end)
        if ok and container then
            return 1
        end
    end
    return 0
end

local function containerAt(object, containerIndex, count)
    if object.getContainerByIndex then
        local ok, container = pcall(function()
            return object:getContainerByIndex(containerIndex)
        end)
        if ok and container then
            return container
        end
    end
    if containerIndex == 0 and object.getContainer then
        local ok, container = pcall(function()
            return object:getContainer()
        end)
        if ok then
            return container
        end
    end
    if count == 1 and containerIndex == 0 and object.getContainer then
        local ok, container = pcall(function()
            return object:getContainer()
        end)
        if ok then
            return container
        end
    end
    return nil
end

-- Every container on the square, in a stable order. index is the tile index.
function World.list(square)
    local rows = {}
    if not square or not square.getObjects then
        return rows
    end
    local objects = square:getObjects()
    if not objects or not objects.size or not objects.get then
        return rows
    end
    local tileIndex = 0
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object then
            local count = containerCount(object)
            for containerIndex = 0, count - 1 do
                local container = containerAt(object, containerIndex, count)
                if container then
                    rows[#rows + 1] = {
                        object = object,
                        container = container,
                        index = tileIndex,
                        containerIndex = containerIndex,
                    }
                    tileIndex = tileIndex + 1
                end
            end
        end
    end
    return rows
end

function World.find(square, tileIndex)
    local rows = World.list(square)
    for i = 1, #rows do
        if rows[i].index == tileIndex then
            return rows[i]
        end
    end
    return nil
end

local function isA(value, className)
    if value == nil or not instanceof then
        return false
    end
    local ok, result = pcall(function()
        return instanceof(value, className)
    end)
    return ok and result and true or false
end

local function containerType(container)
    if not container or not container.getType then
        return ""
    end
    local ok, kind = pcall(function()
        return container:getType()
    end)
    if ok and type(kind) == "string" then
        return kind
    end
    return ""
end

-- Facts Links.exclusion understands. A bag counts as equipped when it is
-- worn, in the hand, or sitting in the player's inventory. A bag that is
-- only on the ground is a world container and can be assigned.
function World.describe(row, player)
    local object = row and row.object
    local container = row and row.container
    local info = { container = container ~= nil }
    if Config.isSorterSpriteName(spriteNameOf(object)) then
        info.sorter = true
    end
    if not container then
        return info
    end
    local parent = nil
    if container.getParent then
        local ok, found = pcall(function()
            return container:getParent()
        end)
        if ok then
            parent = found
        end
    end
    if isA(parent, "IsoPlayer") or isA(object, "IsoPlayer") then
        info.player = true
    end
    if isA(parent, "IsoDeadBody") or isA(object, "IsoDeadBody") then
        info.corpse = true
    end
    if isA(parent, "BaseVehicle") or isA(object, "BaseVehicle") then
        info.vehicle = true
    end
    if object and object.getVehicle then
        local ok, vehicle = pcall(function()
            return object:getVehicle()
        end)
        if ok and vehicle then
            info.vehicle = true
        end
    end
    local kind = containerType(container)
    if kind == "trunk" or kind == "glovebox" or kind == "seat" then
        info.vehicle = true
    end
    if kind == "inventorymale" or kind == "inventoryfemale" then
        info.corpse = true
    end
    if container.getContainingItem then
        local ok, item = pcall(function()
            return container:getContainingItem()
        end)
        if ok and item then
            local equipped = false
            if item.isEquipped then
                local heldOk, held = pcall(function()
                    return item:isEquipped()
                end)
                equipped = heldOk and held and true or false
            end
            if item.isWorn then
                local wornOk, worn = pcall(function()
                    return item:isWorn()
                end)
                if wornOk and worn then
                    equipped = true
                end
            end
            if player and item.isInPlayerInventory then
                local invOk, inside = pcall(function()
                    return item:isInPlayerInventory()
                end)
                if invOk and inside then
                    equipped = true
                end
            end
            if equipped then
                info.equippedBag = true
            end
        end
    end
    return info
end

function World.containerType(container)
    local kind = containerType(container)
    if kind == "" then
        return "container"
    end
    return kind
end

function World.weightAndCapacity(container)
    local weight = 0
    local capacity = 0
    if not container then
        return weight, capacity
    end
    pcall(function()
        if container.getContentsWeight then
            weight = tonumber(container:getContentsWeight()) or 0
        end
        if container.getCapacity then
            capacity = tonumber(container:getCapacity()) or 0
        end
    end)
    return weight, capacity
end

-- The weight a container actually gains when this item is put in it.
-- Unequipped weight includes what is inside a bag, which is what we want:
-- the bag moves as one item and its contents are not weighed a second time.
function World.itemWeight(item)
    if not item then
        return 0
    end
    local value = nil
    pcall(function()
        if item.getUnequippedWeight then
            value = item:getUnequippedWeight()
        end
        if type(value) ~= "number" and item.getActualWeight then
            value = item:getActualWeight()
        end
        if type(value) ~= "number" and item.getWeight then
            value = item:getWeight()
        end
    end)
    if type(value) ~= "number" or value < 0 then
        return 0
    end
    return value
end

-- The sorter id written on this container. The container's own mod data is
-- the spec's copy. The object's slot map is the copy transmitModData is
-- known to save, from step 1. Either one is enough after a reload.
function World.readSorterId(row)
    if not row then
        return nil
    end
    local key = Config.MOD_DATA_KEY
    local container = row.container
    if container and container.getModData then
        local ok, modData = pcall(function()
            return container:getModData()
        end)
        if ok and type(modData) == "table" then
            local saved = modData[key]
            if type(saved) == "table" and saved.sorterId ~= nil then
                return tostring(saved.sorterId)
            end
        end
    end
    local object = row.object
    if object and object.getModData and not Config.isSorterSpriteName(spriteNameOf(object)) then
        local ok, modData = pcall(function()
            return object:getModData()
        end)
        if ok and type(modData) == "table" then
            local saved = modData[key]
            if type(saved) == "table" and type(saved.slots) == "table" then
                local id = saved.slots[tostring(row.containerIndex)]
                if id ~= nil then
                    return tostring(id)
                end
            end
        end
    end
    return nil
end

function World.writeSorterId(row, sorterId)
    if not row or not row.object then
        return
    end
    if Config.isSorterSpriteName(spriteNameOf(row.object)) then
        print("PZSorter: refused to store a link on a Sorter Crate")
        return
    end
    local key = Config.MOD_DATA_KEY
    local container = row.container
    if container and container.getModData then
        pcall(function()
            local modData = container:getModData()
            if sorterId == nil then
                modData[key] = nil
            else
                modData[key] = { sorterId = tostring(sorterId) }
            end
        end)
    end
    if not row.object.getModData then
        return
    end
    local modData = row.object:getModData()
    if type(modData) ~= "table" then
        return
    end
    if type(modData[key]) ~= "table" or modData[key].id ~= nil then
        -- id means this is a sorter record. Do not turn it into slot map.
        if type(modData[key]) == "table" and modData[key].id ~= nil then
            return
        end
        modData[key] = {}
    end
    modData[key].slots = modData[key].slots or {}
    if sorterId == nil then
        modData[key].slots[tostring(row.containerIndex)] = nil
    else
        modData[key].slots[tostring(row.containerIndex)] = tostring(sorterId)
    end
    if row.object.transmitModData then
        pcall(function()
            row.object:transmitModData()
        end)
    end
end

return World
