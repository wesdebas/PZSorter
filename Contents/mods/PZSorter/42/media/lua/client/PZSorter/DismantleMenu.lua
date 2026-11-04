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
require "PZSorter/ItemTags"

PZSorter = PZSorter or {}
PZSorter.DismantleMenu = PZSorter.DismantleMenu or {}

local Menu = PZSorter.DismantleMenu
local Config = PZSorter.Config

if Menu._hooked then
    return Menu
end
Menu._hooked = true

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

function PZSorterDismantleAction:doDismantle(where)
    if self._done then
        print("PZSorter: dismantle already done from " .. tostring(where))
        return
    end
    print("PZSorter: dismantle " .. tostring(where) .. " authority=" .. tostring(Config.onAuthority()))
    if Config.onAuthority() and PZSorter.SorterData and PZSorter.SorterData.dismantleObject then
        local ok, err = pcall(function()
            PZSorter.SorterData.dismantleObject(self.character, self.object)
        end)
        if ok then
            self._done = true
            return
        end
        print("PZSorter: dismantle direct call failed: " .. tostring(err))
    end
    local square = self.object and self.object.getSquare and self.object:getSquare()
    local modData = self.object and self.object.getModData and self.object:getModData()
    local record = modData and modData[Config.MOD_DATA_KEY]
    if not (square and sendClientCommand) then
        print("PZSorter: dismantle has no command path")
        return
    end
    print("PZSorter: command sent Dismantle")
    sendClientCommand(self.character, Config.COMMAND_MODULE, "Dismantle", {
        id = record and record.id or nil,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
    })
    self._done = true
end

function PZSorterDismantleAction:perform()
    print("PZSorter: dismantle perform()")
    self:doDismantle("perform")
    ISBaseTimedAction.perform(self)
end

function PZSorterDismantleAction:complete()
    print("PZSorter: dismantle complete()")
    self:doDismantle("complete")
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
    -- A throw here used to kill the whole right-click menu, and it fired
    -- again on every click. Keep this listener from ever escaping.
    local ok, err = pcall(function()
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
    end)
    if not ok then
        print("PZSorter: dismantle menu failed: " .. tostring(err))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)

return Menu
