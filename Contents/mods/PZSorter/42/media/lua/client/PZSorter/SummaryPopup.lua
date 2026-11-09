-- The small window shown when a sort finishes or is cancelled.
--
-- The sentence is built by SortPlan.summary so the counts match the
-- rules the tests lock. A dedicated server sends that sentence back;
-- single player already has it as the return value of the sort command.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "PZSorter/Config"

PZSorter = PZSorter or {}
PZSorter.SummaryPopup = PZSorter.SummaryPopup or {}

local Popup = PZSorter.SummaryPopup
local Config = PZSorter.Config

if Popup._loaded then
    return Popup
end
Popup._loaded = true

local current = nil

local function wrap(text, limit)
    local lines = {}
    if type(text) ~= "string" or text == "" then
        return lines
    end
    local line = ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word > limit then
            lines[#lines + 1] = line
            line = word
        else
            line = line .. " " .. word
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

if not ISCollapsableWindow then
    print("PZSorter: summary window missing")
    return Popup
end

PZSorterSummaryPopup = ISCollapsableWindow:derive("PZSorterSummaryPopup")

function PZSorterSummaryPopup:new(x, y, width, height, message)
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self
    window.message = message
    window.title = getText and getText("IGUI_PZSorter_SummaryTitle") or "Sort finished"
    if window.setResizable then
        window:setResizable(false)
    end
    return window
end

function PZSorterSummaryPopup:initialise()
    ISCollapsableWindow.initialise(self)
    local lines = wrap(self.message, 46)
    local top = 28
    for i = 1, #lines do
        local label = ISLabel:new(16, top, 18, lines[i], 1, 1, 1, 1, UIFont.Small, true)
        label:initialise()
        self:addChild(label)
        top = top + 18
    end
    local ok = ISButton:new((self.width - 80) / 2, top + 8, 80, 22, getText and getText("IGUI_PZSorter_NameOk") or "OK", self, PZSorterSummaryPopup.onOk)
    ok:initialise()
    ok:instantiate()
    self:addChild(ok)
    local height = top + 44
    if self.setHeight then
        self:setHeight(height)
    else
        self.height = height
    end
end

function PZSorterSummaryPopup:onOk()
    self:close()
end

function PZSorterSummaryPopup:close()
    if current == self then
        current = nil
    end
    ISCollapsableWindow.close(self)
end

function Popup.show(message)
    if type(message) ~= "string" or message == "" then
        return
    end
    print("PZSorter: summary popup " .. message)
    if current and current.close then
        current:close()
    end
    local width = 460
    local height = 160
    local screenW = 800
    local screenH = 600
    if getCore and getCore().getScreenWidth then
        screenW = getCore():getScreenWidth()
        screenH = getCore():getScreenHeight()
    end
    local window = PZSorterSummaryPopup:new((screenW - width) / 2, (screenH - height) / 2, width, height, message)
    window:initialise()
    window:addToUIManager()
    if window.setVisible then
        window:setVisible(true)
    end
    if window.bringToTop then
        window:bringToTop()
    end
    current = window
end

if Events and Events.OnServerCommand and Events.OnServerCommand.Add then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= Config.COMMAND_MODULE or command ~= "SortSummary" then
            return
        end
        if type(args) == "table" and type(args.text) == "string" then
            Popup.show(args.text)
        end
    end)
end

print("PZSorter: summary popup loaded (0.3.0)")

return Popup
