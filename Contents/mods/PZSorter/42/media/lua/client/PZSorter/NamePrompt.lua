-- The name box that opens after a Sorter Crate is placed.
--
-- The server has already stored a suggested name ("Sorter 1", then "Sorter
-- 2", and so on) on the crate. This box shows that suggestion. OK sends the
-- typed name to the server, which trims it and refuses an empty name or a
-- name over 24 characters. Closing the box, or choosing "Use default", keeps
-- the suggestion. The suggestion is already a legal name, so the crate is
-- never left unnamed.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISLabel"
require "PZSorter/Config"
require "PZSorter/Names"

PZSorter = PZSorter or {}
PZSorter.NamePrompt = PZSorter.NamePrompt or {}

local Prompt = PZSorter.NamePrompt
local Config = PZSorter.Config

if Prompt._hooked then
    return Prompt
end
Prompt._hooked = true

-- Crates we have seen but not named yet. An array, not the object as a key:
-- Kahlua's userdata is a poor table key.
local waiting = {}
local uiOpen = false

local function recordOf(object)
    if not object or not object.getModData then
        return nil
    end
    local modData = object:getModData()
    if not modData then
        return nil
    end
    return modData[Config.MOD_DATA_KEY]
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

local function isSorter(object)
    return Config.isSorterSpriteName(spriteNameOf(object))
end

local function remember(object)
    if not isSorter(object) then
        return
    end
    for i = 1, #waiting do
        if waiting[i] == object then
            return
        end
    end
    waiting[#waiting + 1] = object
end

function Prompt.watch(object)
    remember(object)
end

local function applyLocalName(object, name, confirmed)
    local record = recordOf(object)
    if not record then
        return
    end
    record.name = name
    record.nameConfirmed = confirmed and true or false
    if PZSorter.Tooltip and PZSorter.Tooltip.applyName then
        PZSorter.Tooltip.applyName(object)
    end
end

local function sendName(player, object, name)
    local record = recordOf(object)
    local square = object and object.getSquare and object:getSquare()
    if not record or not square then
        return
    end
    -- Show the name at once. The server writes the same trimmed text and
    -- sends it back; if it refuses, NameRejected reopens the box.
    applyLocalName(object, name, true)
    if sendClientCommand then
        sendClientCommand(player, Config.COMMAND_MODULE, "SetName", {
            id = record.id,
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            name = name,
        })
    end
end

PZSorterNamePromptUI = ISPanel:derive("PZSorterNamePromptUI")

function PZSorterNamePromptUI:new(player, object, suggested, errorReason)
    local width = 340
    local height = 168
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local panel = ISPanel:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.player = player
    panel.object = object
    panel.suggested = suggested
    panel.errorReason = errorReason
    panel.moveWithMouse = true
    panel.backgroundColor = { r = 0.08, g = 0.07, b = 0.06, a = 0.92 }
    panel.borderColor = { r = 0.84, g = 0.66, b = 0.16, a = 1 }
    return panel
end

function PZSorterNamePromptUI:initialise()
    ISPanel.initialise(self)
    local title = ISLabel:new(14, 12, 20, getText("IGUI_PZSorter_NameTitle"), 1, 1, 1, 1, UIFont.Medium, true)
    title:initialise()
    self:addChild(title)

    self.entry = ISTextEntryBox:new(self.suggested or "", 14, 42, self.width - 28, 22)
    self.entry:initialise()
    self.entry:instantiate()
    if self.entry.setMaxTextLength then
        -- The server is the real limit. This just stops a huge paste.
        self.entry:setMaxTextLength(48)
    end
    self:addChild(self.entry)

    self.hint = ISLabel:new(14, 70, 18, getText("IGUI_PZSorter_NameHint"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    self.hint:initialise()
    self:addChild(self.hint)

    self.errorLabel = ISLabel:new(14, 90, 18, "", 1, 0.45, 0.4, 1, UIFont.Small, true)
    self.errorLabel:initialise()
    self:addChild(self.errorLabel)
    if self.errorReason then
        self:showError(self.errorReason)
    end

    self.keepButton = ISButton:new(14, self.height - 38, 140, 24, getText("IGUI_PZSorter_NameKeep"), self, PZSorterNamePromptUI.onKeep)
    self.keepButton:initialise()
    self.keepButton:instantiate()
    self:addChild(self.keepButton)

    self.okButton = ISButton:new(self.width - 92, self.height - 38, 78, 24, getText("IGUI_PZSorter_NameOk"), self, PZSorterNamePromptUI.onOk)
    self.okButton:initialise()
    self.okButton:instantiate()
    self:addChild(self.okButton)
end

function PZSorterNamePromptUI:showError(reason)
    local key = "IGUI_PZSorter_NameEmpty"
    if reason == "too_long" then
        key = "IGUI_PZSorter_NameLong"
    end
    self.errorLabel:setName(getText(key))
end

function PZSorterNamePromptUI:close()
    uiOpen = false
    self:setVisible(false)
    self:removeFromUIManager()
end

function PZSorterNamePromptUI:onOk()
    local raw = ""
    if self.entry.getText then
        raw = self.entry:getText()
    end
    local name, reason = PZSorter.Names.validate(raw)
    if not name then
        -- Leave the box open. An empty name or a 25 character name is not stored.
        self:showError(reason)
        return
    end
    sendName(self.player, self.object, name)
    self:close()
end

function PZSorterNamePromptUI:onKeep()
    local suggested = self.suggested or "Sorter 1"
    local name = PZSorter.Names.validate(suggested)
    if not name then
        name = "Sorter 1"
    end
    sendName(self.player, self.object, name)
    self:close()
end

function PZSorterNamePromptUI:onKeyPressed(key)
    if not Keyboard then
        return
    end
    if key == Keyboard.KEY_ESCAPE then
        self:onKeep()
    elseif key == Keyboard.KEY_RETURN or key == Keyboard.KEY_KP_ENTER then
        self:onOk()
    end
end

local function openBox(player, object, suggested, errorReason)
    if uiOpen then
        return
    end
    uiOpen = true
    local panel = PZSorterNamePromptUI:new(player, object, suggested, errorReason)
    panel:initialise()
    panel:addToUIManager()
    if panel.setAlwaysOnTop then
        panel:setAlwaysOnTop(true)
    end
    if panel.entry and panel.entry.focus then
        panel.entry:focus()
    end
end

local function playerNear(player, object)
    local square = object.getSquare and object:getSquare()
    local playerSquare = player.getSquare and player:getSquare()
    if not square or not playerSquare then
        return false
    end
    if square:getZ() ~= playerSquare:getZ() then
        return false
    end
    local dx = math.abs(square:getX() - playerSquare:getX())
    local dy = math.abs(square:getY() - playerSquare:getY())
    -- You are standing at the crate when you place it. A chunk that loads
    -- a neighbour's unnamed crate across the base should not pop the box.
    return math.max(dx, dy) <= 3
end

local function consider(object)
    if uiOpen then
        return
    end
    local record = recordOf(object)
    if not record or record.nameConfirmed then
        return
    end
    local player = getSpecificPlayer(0)
    if not player or not playerNear(player, object) then
        return
    end
    local ok, err = pcall(function()
        openBox(player, object, record.name)
    end)
    if not ok then
        -- The crate already has its suggested name saved. A broken box
        -- should not stop the game; the name can still be read on hover.
        uiOpen = false
        print("PZSorter: name prompt failed: " .. tostring(err))
    end
end

local function onTick()
    if #waiting == 0 or uiOpen then
        return
    end
    local still = {}
    for i = 1, #waiting do
        local object = waiting[i]
        local square = object and object.getSquare and object:getSquare()
        if square then
            local record = recordOf(object)
            if record and not record.nameConfirmed then
                still[#still + 1] = object
                consider(object)
            elseif record == nil then
                -- Mod data may arrive a moment after the object in co-op.
                still[#still + 1] = object
            end
        end
    end
    waiting = still
end

local function onObjectAdded(object)
    if isClient and not isClient() then
        return
    end
    remember(object)
end

local function onLoadGridsquare(square)
    if isClient and not isClient() then
        return
    end
    if not square or not square.getObjects then
        return
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if isSorter(object) then
            remember(object)
            if PZSorter.Tooltip and PZSorter.Tooltip.applyName then
                PZSorter.Tooltip.applyName(object)
            end
        end
    end
end

local function onServerCommand(module, command, args)
    if module ~= Config.COMMAND_MODULE or command ~= "NameRejected" then
        return
    end
    if type(args) ~= "table" then
        return
    end
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    local cell = getCell()
    if not cell then
        return
    end
    local square = cell:getGridSquare(args.x, args.y, args.z)
    if not square then
        return
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local record = recordOf(object)
        if record and tostring(record.id) == tostring(args.id) then
            record.nameConfirmed = false
            remember(object)
            if not uiOpen then
                local ok, err = pcall(function()
                    openBox(player, object, record.name, args.reason)
                end)
                if not ok then
                    print("PZSorter: could not reopen name prompt: " .. tostring(err))
                end
            end
            return
        end
    end
end

Events.OnTick.Add(onTick)
Events.OnObjectAdded.Add(onObjectAdded)
Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnServerCommand.Add(onServerCommand)

print("PZSorter: name prompt loaded (0.1.0)")

return Prompt
