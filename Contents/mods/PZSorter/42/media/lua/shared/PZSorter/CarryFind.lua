-- Find the Sorter Crate item a player is carrying.
--
-- Shared on purpose. Pickup runs from the client action, and Unassign
-- runs from the command handler. In single player those are the same
-- state. On a dedicated server the handler still has to see the item.

PZSorter = PZSorter or {}
PZSorter.CarryFind = PZSorter.CarryFind or {}

local Find = PZSorter.CarryFind

require "PZSorter/Config"
require "PZSorter/Carry"

local Config = PZSorter.Config
local FULL_TYPE = "PZSorter.SorterCrate"

local function packedOf(item)
    if not item or not item.getModData then
        return nil
    end
    local ok, modData = pcall(function()
        return item:getModData()
    end)
    if not ok or type(modData) ~= "table" then
        return nil
    end
    local packed = modData[Config.MOD_DATA_KEY]
    if type(packed) ~= "table" or packed.id == nil then
        return nil
    end
    return packed
end

local function eachItem(inventory, visit)
    if not inventory or not inventory.getItems then
        return nil
    end
    local items = inventory:getItems()
    if not items or not items.size then
        return nil
    end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local done = visit(item)
        if done then
            return done
        end
        if item and item.getInventory then
            local ok, inner = pcall(function()
                return item:getInventory()
            end)
            if ok and inner and inner ~= inventory then
                local nested = eachItem(inner, visit)
                if nested then
                    return nested
                end
            end
        end
    end
    return nil
end

local function scanPlayer(player, visit)
    if not player or not player.getInventory then
        return nil
    end
    local ok, inventory = pcall(function()
        return player:getInventory()
    end)
    if not ok then
        return nil
    end
    return eachItem(inventory, visit)
end

function Find.find(id)
    local function visit(item)
        local packed = packedOf(item)
        if packed and tostring(packed.id) == tostring(id) then
            return { item = item, packed = packed }
        end
        return nil
    end
    if getSpecificPlayer then
        for playerNum = 0, 3 do
            local found = scanPlayer(getSpecificPlayer(playerNum), visit)
            if found then
                return found.item, found.packed
            end
        end
    end
    if getOnlinePlayers then
        local ok, players = pcall(getOnlinePlayers)
        if ok and players and players.size then
            for i = 0, players:size() - 1 do
                local found = scanPlayer(players:get(i), visit)
                if found then
                    return found.item, found.packed
                end
            end
        end
    end
    return nil, nil
end

-- The moveable action just created this. It has the right type and does
-- not yet carry a sorter id. Fall back to the last Sorter Crate item.
function Find.findFresh(player)
    local fresh = nil
    local fallback = nil
    scanPlayer(player, function(item)
        if item and item.getFullType and item:getFullType() == FULL_TYPE then
            fallback = item
            if not packedOf(item) then
                fresh = item
            end
        end
        return nil
    end)
    return fresh or fallback
end

function Find.write(item, packed)
    if not item or not item.getModData or type(packed) ~= "table" then
        return
    end
    item:getModData()[Config.MOD_DATA_KEY] = packed
    if packed.name then
        PZSorter.Carry.nameItem(item, packed.name)
    end
    if item.transmitModData then
        pcall(function()
            item:transmitModData()
        end)
    end
end

return Find
