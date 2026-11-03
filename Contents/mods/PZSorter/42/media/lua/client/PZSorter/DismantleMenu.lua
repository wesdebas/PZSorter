-- "Dismantle" on the Sorter Crate's right-click menu.
--
-- The tile is not marked CanScrap. Vanilla scrap would hand back nails (that
-- is what a Wood material returns) and would only sometimes return the metal
-- sheet. Our recipe is planks, screws, and one sheet, and the sheet always
-- comes back, so dismantle is our own timed action. The server does the
-- actual removal and the item grants. This file only asks.
--
-- The file is named DismantleMenu, not Dismantle. The shared rules already
-- use the require name PZSorter/Dismantle, and two files with that name
-- would overwrite each other.

require "TimedActions/ISBaseTimedAction"
require "PZSorter/Config"
require "PZSorter/Dismantle"

PZSorter = PZSorter or {}
PZSorter.DismantleMenu = PZSorter.DismantleMenu or {}

local Menu = PZSorter.DismantleMenu
local Config = PZSorter.Config

if Menu._hooked then
    return Menu
end
Menu._hooked = true

local PROBE_TAGS = {
    "base:hammer",
    "hammer",
    "base:saw",
    "saw",
    "base:hacksaw",
    "hacksaw",
    "base:smallsaw",
    "smallsaw",
}

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

local function findSorter(worldobjects)
    if not worldobjects then
        return nil
    end
    if worldobjects.size and worldobjects.get then
        for i = 0, worldobjects:size() - 1 do
            local object = worldobjects:get(i)
            if Config.isSorterSpriteName(spriteNameOf(object)) then
                return object
            end
        end
        return nil
    end
    if type(worldobjects) == "table" then
        for _, object in ipairs(worldobjects) do
            if Config.isSorterSpriteName(spriteNameOf(object)) then
                return object
            end
        end
    end
    return nil
end

local function tagsHeld(player)
    local found = {}
    local inventory = player and player.getInventory and player:getInventory()
    if not inventory then
        return found
    end
    for _, tag in ipairs(PROBE_TAGS) do
        local has = false
        if inventory.containsTag and inventory:containsTag(tag) then
            has = true
        elseif inventory.getFirstTagRecurse and inventory:getFirstTagRecurse(tag) then
            has = true
        elseif inventory.getFirstTag and inventory:getFirstTag(tag) then
            has = true
        end
        if has then
            found[#found + 1] = tag
        end
    end
    return found
end

PZSorterDismantleAction = ISBaseTimedAction:derive("PZSorterDismantleAction")

function PZSorterDismantleAction:new(player, object)
    -- ISBaseTimedAction.new wires the action into the queue. Building the
    -- table by hand skips that and the bar never finishes on current builds.
    local action = ISBaseTimedAction.new(self, player)
    action.object = object
    -- A couple of seconds. Not the sort timer (that is a later step).
    action.maxTime = 160
    action.stopOnWalk = true
    action.stopOnRun = true
    action.caloriesModifier = 4
    if player and player.isTimedActionInstant and player:isTimedActionInstant() then
        action.maxTime = 1
    end
    return action
end

function PZSorterDismantleAction:isValid()
    if not self.object or not self.object.getSquare then
        return false
    end
    return self.object:getSquare() ~= nil
end

function PZSorterDismantleAction:waitToStart()
    if self.character and self.character.faceThisObject then
        self.character:faceThisObject(self.object)
    end
    if self.character and self.character.shouldBeTurning then
        return self.character:shouldBeTurning()
    end
    return false
end

function PZSorterDismantleAction:start()
    -- The saw animation is what vanilla disassembly plays. If this build
    -- renamed it, the bar still runs; the pcall keeps a missing anim from
    -- cancelling the action.
    if self.setActionAnim then
        pcall(function()
            self:setActionAnim("SawLog")
        end)
    end
end

function PZSorterDismantleAction:update()
    if self.character and self.character.faceThisObject then
        self.character:faceThisObject(self.object)
    end
end

function PZSorterDismantleAction:send()
    -- perform() runs on the client. complete() is the hook some Build 42
    -- builds call instead, including on the listen server. Either one is
    -- enough, and the guard stops the crate being dismantled twice.
    if self._sent then
        return
    end
    local square = self.object and self.object.getSquare and self.object:getSquare()
    local modData = self.object and self.object.getModData and self.object:getModData()
    local record = modData and modData[Config.MOD_DATA_KEY]
    if not (square and record and sendClientCommand) then
        -- Leave _sent clear so complete() can try if perform() ran first
        -- and the record was not on the object yet.
        return
    end
    self._sent = true
    sendClientCommand(self.character, Config.COMMAND_MODULE, "Dismantle", {
        id = record.id,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
    })
end

function PZSorterDismantleAction:perform()
    self:send()
    ISBaseTimedAction.perform(self)
end

function PZSorterDismantleAction:complete()
    self:send()
    return true
end

function PZSorterDismantleAction:stop()
    ISBaseTimedAction.stop(self)
end

local function startDismantle(player, object)
    if not player or not object then
        return
    end
    if luautils and luautils.walkAdj then
        -- walkAdj queues a walk to a free square next to the crate. The
        -- crate itself is solid, so walking onto its square would fail.
        luautils.walkAdj(player, object:getSquare())
    end
    ISTimedActionQueue.add(PZSorterDismantleAction:new(player, object))
end

local function onFillMenu(playerNum, context, worldobjects, test)
    -- The game probes the menu with test == true and then builds it for
    -- real. Adding the option both times is what the vanilla menus do; the
    -- probe throws the probe menu away.
    if not context or not context.addOption then
        return
    end
    local object = findSorter(worldobjects)
    if not object then
        return
    end
    local player = getSpecificPlayer(playerNum)
    local option = context:addOption(getText("IGUI_PZSorter_Dismantle"), player, startDismantle, object)
    if not PZSorter.Dismantle.hasRequiredTools(tagsHeld(player)) then
        option.notAvailable = true
        if ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_PZSorter_DismantleNeedTools")
            option.toolTip = tip
        end
    end
    if test then
        return
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)

return Menu
