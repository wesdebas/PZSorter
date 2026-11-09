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
require "PZSorter/BuildHook"

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
-- The crate whose box is on screen. A second open for that same crate
-- (the placement hook plus a command, or the hook running twice) is ignored
-- until this box closes. Rename after that still opens.
local openKey = nil

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
    if not square then
        print("PZSorter: sendName has no square")
        return
    end
    print("PZSorter: name chosen " .. tostring(name))
    -- Show the name at once. The save is written here in single player,
    -- because isClient() and isServer() are both false and a command to
    -- ourselves is not delivered.
    applyLocalName(object, name, true)
    if PZSorter.Tooltip and PZSorter.Tooltip.applyName then
        PZSorter.Tooltip.applyName(object)
    end
    local args = {
        id = record and record.id or nil,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        name = name,
    }
    if Config.onAuthority() and PZSorter.SorterData and PZSorter.SorterData.setName then
        print("PZSorter: storing name directly")
        PZSorter.SorterData.setName(player, args)
        return
    end
    if sendClientCommand then
        print("PZSorter: command sent SetName")
        sendClientCommand(player, Config.COMMAND_MODULE, "SetName", args)
        return
    end
    print("PZSorter: no way to store the name")
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
    openKey = nil
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

local function promptKey(object)
    local record = recordOf(object)
    if record and record.id ~= nil then
        return "id:" .. tostring(record.id)
    end
    local square = object and object.getSquare and object:getSquare()
    if square and square.getX then
        return "sq:" .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
    end
    return nil
end

local function openBox(player, object, suggested, errorReason)
    local key = promptKey(object)
    if uiOpen or (key ~= nil and openKey == key) then
        print("PZSorter: prompt already open for this crate")
        return
    end
    uiOpen = true
    openKey = key
    print("PZSorter: prompt opened suggested=" .. tostring(suggested))
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
        openKey = nil
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
    if not Config.onPlayer() then
        return
    end
    remember(object)
end

local function onLoadGridsquare(square)
    if not Config.onPlayer() then
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

function Prompt.onBuilt(object, character)
    print("PZSorter: prompt onBuilt player=" .. tostring(Config.onPlayer()))
    if not Config.onPlayer() then
        print("PZSorter: prompt skipped, dedicated server has no ui")
        return
    end
    local record = recordOf(object)
    -- promptFor returns nil once the name is confirmed. A missing record
    -- still opens the box: the build can finish on the client before the
    -- server's save data has arrived, and "Sorter 1" is the same default.
    if record and record.nameConfirmed then
        return
    end
    local payload = PZSorter.Names.promptFor(record, false)
    local suggested = payload and payload.name or "Sorter 1"
    local player = character
    if not player or not player.getPlayerNum then
        player = getSpecificPlayer(0)
    end
    if not player then
        return
    end
    local ok, err = pcall(function()
        openBox(player, object, suggested)
    end)
    if not ok then
        uiOpen = false
        openKey = nil
        print("PZSorter: name prompt failed: " .. tostring(err))
    end
end

local function findSorterAt(x, y, z, id)
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
        if isSorter(object) then
            local record = recordOf(object)
            if id == nil or (record and tostring(record.id) == tostring(id)) then
                return object
            end
        end
    end
    return nil
end

function Prompt.beginRename(player, object)
    print("PZSorter: Rename clicked")
    if not player or not object then
        print("PZSorter: Rename missing player or crate")
        return
    end
    local record = recordOf(object)
    local suggested = "Sorter 1"
    if record then
        local payload = PZSorter.Names.promptFor(record, true)
        if payload and payload.name then
            suggested = payload.name
        end
    else
        local container = object.getContainer and object:getContainer()
        local custom = container and container.getCustomName and container:getCustomName()
        local kept = PZSorter.Names.validate(custom)
        if kept and kept ~= "Sorter Crate" then
            suggested = kept
        end
        print("PZSorter: Rename has no saved record, suggesting " .. suggested)
    end
    local ok, err = pcall(function()
        openBox(player, object, suggested)
    end)
    if not ok then
        uiOpen = false
        openKey = nil
        print("PZSorter: Rename box failed: " .. tostring(err))
    end
end

local function onFillRename(playerNum, context, worldobjects, test)
    -- Separate from dismantle. A tool-tag error must not hide Rename.
    local ok, err = pcall(function()
        if not context or not context.addOption then
            return
        end
        local object = nil
        if worldobjects and worldobjects.size and worldobjects.get then
            for i = 0, worldobjects:size() - 1 do
                local candidate = worldobjects:get(i)
                if isSorter(candidate) then
                    object = candidate
                    break
                end
            end
        elseif type(worldobjects) == "table" then
            for _, candidate in ipairs(worldobjects) do
                if isSorter(candidate) then
                    object = candidate
                    break
                end
            end
        end
        if not object then
            return
        end
        local player = getSpecificPlayer(playerNum)
        print("PZSorter: Rename added to the menu")
        context:addOption(getText("IGUI_PZSorter_Rename"), player, Prompt.beginRename, object)
        if test then
            return
        end
    end)
    if not ok then
        print("PZSorter: rename menu failed: " .. tostring(err))
    end
end

local function onServerCommand(module, command, args)
    if module ~= Config.COMMAND_MODULE then
        return
    end
    if command == "OpenName" and type(args) == "table" then
        local player = getSpecificPlayer(0)
        local object = findSorterAt(args.x, args.y, args.z, args.id)
        if object and PZSorter.Tooltip and PZSorter.Tooltip.applyName then
            local record = recordOf(object)
            if record and args.name and not record.nameConfirmed then
                record.name = args.name
            end
            PZSorter.Tooltip.applyName(object)
        end
        if not player then
            return
        end
        local suggested = args.name or "Sorter 1"
        if object then
            local record = recordOf(object)
            if record and record.nameConfirmed then
                return
            end
        end
        local ok, err = pcall(function()
            openBox(player, object, suggested)
        end)
        if not ok then
            uiOpen = false
            openKey = nil
            print("PZSorter: name prompt failed: " .. tostring(err))
        end
        return
    end
    if command ~= "NameRejected" then
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
Events.OnFillWorldObjectContextMenu.Add(onFillRename)

print("PZSorter: name prompt loaded (0.3.0)")

return Prompt
