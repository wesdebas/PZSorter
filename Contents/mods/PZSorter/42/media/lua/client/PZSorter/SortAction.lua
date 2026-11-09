-- The timed action that plays while a crate is sorted.
--
-- The character stays at the crate and a progress bar fills. The length
-- comes from how many items are in the crate and how much they weigh.
-- About 50 light items is about 10 seconds. Sort speed Instant, or the
-- debug "instant actions" cheat, finishes on the next tick.
--
-- This file does not move items. Each slice of the bar asks the server
-- (SortRunner) to commit the next item. Walking away or getting hit stops
-- the action. The steps that already ran stay done, because stop does not
-- ask for them to be undone.

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWalkToTimedAction"
require "PZSorter/Config"
require "PZSorter/SortPlan"
require "PZSorter/Range"
require "PZSorter/WorldContainers"

PZSorter = PZSorter or {}
PZSorter.SortAction = PZSorter.SortAction or {}

local SortAction = PZSorter.SortAction

if SortAction._loaded then
    return SortAction
end
SortAction._loaded = true

local Config = PZSorter.Config
local Plan = PZSorter.SortPlan
local Range = PZSorter.Range
local World = PZSorter.WorldContainers

-- Same reach the server uses for "standing at the crate".
local REACH = 3

local function request(player, command, args)
    if PZSorter.Commands and PZSorter.Commands.request then
        return PZSorter.Commands.request(player, command, args)
    end
    if sendClientCommand then
        print("PZSorter: command sent " .. tostring(command))
        sendClientCommand(player, Config.COMMAND_MODULE, command, args)
        return nil
    end
    print("PZSorter: no way to run " .. tostring(command))
    return nil
end

local function showSummary(result)
    local text = nil
    if type(result) == "string" then
        text = result
    elseif type(result) == "table" then
        text = result.summary
    end
    if type(text) ~= "string" or text == "" then
        return
    end
    if PZSorter.SummaryPopup and PZSorter.SummaryPopup.show then
        PZSorter.SummaryPopup.show(text)
    else
        print("PZSorter: sort summary " .. text)
    end
end

local function crateContents(object)
    local count = 0
    local weight = 0
    if not object or not object.getContainer then
        return count, weight
    end
    local container = object:getContainer()
    if not container or not container.getItems then
        return count, weight
    end
    local items = container:getItems()
    if not items or not items.size or not items.get then
        return count, weight
    end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            count = count + 1
            weight = weight + World.itemWeight(item)
        end
    end
    return count, weight
end

local function distanceTo(player, object)
    if not player or not player.getSquare or not object or not object.getSquare then
        return nil
    end
    local playerSquare = player:getSquare()
    local objectSquare = object:getSquare()
    if not playerSquare or not objectSquare or not playerSquare.getX or not objectSquare.getX then
        return nil
    end
    if playerSquare:getZ() ~= objectSquare:getZ() then
        return nil
    end
    return Range.chebyshev(playerSquare:getX(), playerSquare:getY(), objectSquare:getX(), objectSquare:getY())
end

local function sorterArgs(object)
    local square = object and object.getSquare and object:getSquare()
    local modData = object and object.getModData and object:getModData()
    local record = modData and modData[Config.MOD_DATA_KEY]
    if not square or type(record) ~= "table" then
        return nil
    end
    return {
        sorterId = record.id,
        sorterX = square:getX(),
        sorterY = square:getY(),
        sorterZ = square:getZ(),
    }
end

if not ISBaseTimedAction then
    print("PZSorter: ISBaseTimedAction missing, sort action not loaded")
    return SortAction
end

PZSorterSortAction = ISBaseTimedAction:derive("PZSorterSortAction")

function PZSorterSortAction:new(player, object)
    local action = ISBaseTimedAction:new(player)
    setmetatable(action, self)
    self.__index = self
    action.object = object
    action.args = sorterArgs(object)
    action.sent = 0
    action._started = false
    action._ended = false
    action._failed = false
    action._cancelReason = nil
    local count, weight = crateContents(object)
    local speed = Plan.currentSpeed()
    if player and player.isTimedActionInstant then
        local ok, instant = pcall(player.isTimedActionInstant, player)
        if ok and instant then
            speed = Plan.SPEED_INSTANT
            print("PZSorter: sort speed instant from the player")
        end
    end
    action.instant = speed == Plan.SPEED_INSTANT
    action.steps = count
    action.maxTime = Plan.duration(count, weight, speed)
    -- The engine's stopOnWalk flag also trips for a frame after the walk-to
    -- finishes, which would cancel the sort before it moved anything. Distance
    -- and isPlayerMoving are checked once the action has actually started.
    action.stopOnWalk = false
    action.stopOnRun = false
    action.stopOnAim = false
    action.useProgressBar = true
    action.forceProgressBar = true
    print("PZSorter: sort action items=" .. tostring(count)
        .. " weight=" .. string.format("%.2f", weight)
        .. " speed=" .. speed
        .. " maxTime=" .. tostring(action.maxTime))
    return action
end

function PZSorterSortAction:isValid()
    if self._failed or self._ended then
        return false
    end
    local character = self.character
    if not character then
        self._cancelReason = "stopped"
        return false
    end
    if character.isDead and character:isDead() then
        self._cancelReason = "dead"
        return false
    end
    if not self.object or not self.object.getSquare or not self.object:getSquare() then
        self._cancelReason = "crate gone"
        return false
    end
    if character.isBumped and character:isBumped() then
        self._cancelReason = "attacked"
        return false
    end
    if character.getHitReaction then
        local ok, reaction = pcall(character.getHitReaction, character)
        if ok and type(reaction) == "string" and reaction ~= "" then
            self._cancelReason = "attacked"
            return false
        end
    end
    -- A handful of ticks covers the handoff from walking up to the crate.
    -- After that, stepping away or walking off cancels, and moved items stay.
    if (self._ticks or 0) >= 8 then
        if character.isPlayerMoving and character:isPlayerMoving() then
            self._cancelReason = "moved"
            return false
        end
        local distance = distanceTo(character, self.object)
        if distance == nil or distance > REACH then
            self._cancelReason = "moved"
            return false
        end
    end
    return true
end

function PZSorterSortAction:isValidStart()
    return self:isValid()
end

function PZSorterSortAction:start()
    self._started = true
    pcall(function()
        if self.setActionAnim then
            self:setActionAnim("Loot")
        end
    end)
    if not self.args then
        print("PZSorter: sort did not start, crate has no save data")
        self._failed = true
        return
    end
    local result = request(self.character, "SortBegin", self.args)
    if result == false then
        print("PZSorter: sort did not start")
        self._failed = true
        return
    end
    if type(result) == "table" and type(result.steps) == "number" then
        self.steps = result.steps
    end
    print("PZSorter: sort action started steps=" .. tostring(self.steps) .. " instant=" .. tostring(self.instant))
end

function PZSorterSortAction:update()
    self._ticks = (self._ticks or 0) + 1
    if self.instant or self._ended or not self._started or self._failed then
        return
    end
    local steps = self.steps or 0
    if steps <= 0 or not self.args then
        return
    end
    local delta = 0
    if self.getJobDelta then
        local ok, value = pcall(self.getJobDelta, self)
        if ok and type(value) == "number" then
            delta = value
        end
    end
    local target = math.floor(delta * steps)
    if delta >= 1 then
        target = steps
    end
    while self.sent < target do
        request(self.character, "SortStep", self.args)
        self.sent = self.sent + 1
    end
end

function PZSorterSortAction:perform()
    if self._ended then
        return
    end
    self._ended = true
    SortAction._busy = false
    print("PZSorter: sort action finished")
    if self._started and not self._failed and self.args then
        showSummary(request(self.character, "SortFinish", self.args))
    end
    ISBaseTimedAction.perform(self)
end

function PZSorterSortAction:stop()
    if self._ended then
        ISBaseTimedAction.stop(self)
        return
    end
    self._ended = true
    SortAction._busy = false
    local reason = self._cancelReason
    if not reason and self.character and self.character.isPlayerMoving and self.character:isPlayerMoving() then
        reason = "moved"
    end
    if not reason then
        reason = "stopped"
    end
    print("PZSorter: sort cancelled, " .. reason)
    -- Items already moved stay. Cancel only drops the steps that have not
    -- been sent, which the server has not applied.
    if self._started and not self._failed and self.args then
        showSummary(request(self.character, "SortCancel", self.args))
    end
    ISBaseTimedAction.stop(self)
end

function SortAction.start(player, object)
    if not player or not object then
        print("PZSorter: sort missing player or crate")
        return
    end
    if SortAction._busy then
        print("PZSorter: sort already running")
        return
    end
    local square = object.getSquare and object:getSquare()
    if not square then
        print("PZSorter: sort crate has no square")
        return
    end
    if not ISTimedActionQueue or not ISTimedActionQueue.add then
        print("PZSorter: timed action queue missing")
        return
    end
    local action = PZSorterSortAction:new(player, object)
    SortAction._busy = true
    if ISWalkToTimedAction and AdjacentFreeTileFinder and AdjacentFreeTileFinder.Find then
        local ok, adjacent = pcall(AdjacentFreeTileFinder.Find, square, player)
        if ok and adjacent then
            print("PZSorter: sort walking to the crate")
            local queued, err = pcall(function()
                ISTimedActionQueue.add(ISWalkToTimedAction:new(player, adjacent))
            end)
            if not queued then
                print("PZSorter: sort walk failed: " .. tostring(err))
            end
        end
    end
    ISTimedActionQueue.add(action)
    print("PZSorter: sort queued")
end

print("PZSorter: sort action loaded (0.3.0)")

return SortAction
