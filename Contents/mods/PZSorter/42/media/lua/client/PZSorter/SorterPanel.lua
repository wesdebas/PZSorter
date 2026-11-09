-- The list of containers linked to one Sorter Crate.
--
-- Right-click the crate and choose Open Sorter. The header is the crate's
-- name. Each link is a row: the container's own name if it was renamed,
-- otherwise the auto name, the filter ("Food: 12 items", "Hammer, Screws",
-- or "No filter"), a priority from 1 to 9, a bar of how full it is, a dot,
-- Edit filter, and Remove. Sort runs the timed action. Preview is still
-- disabled; it is a later step. Renaming a row from this panel is a later
-- step. A name the container already has is shown now.
--
-- Green means the container is in range. Grey means it is outside the
-- sandbox square, or its square is not loaded. Red means the square is
-- loaded and that index is gone (picked up or destroyed). A red row stays
-- until Remove.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "PZSorter/Config"
require "PZSorter/Range"
require "PZSorter/Links"
require "PZSorter/Filter"
require "PZSorter/WorldContainers"
require "PZSorter/Highlight"
require "PZSorter/FilterChecklist"
require "PZSorter/FilterEditor"
require "PZSorter/SortAction"
require "PZSorter/SummaryPopup"

PZSorter = PZSorter or {}
PZSorter.SorterPanel = PZSorter.SorterPanel or {}

local PanelApi = PZSorter.SorterPanel
local Config = PZSorter.Config
local Range = PZSorter.Range
local Links = PZSorter.Links
local Filter = PZSorter.Filter
local World = PZSorter.WorldContainers

PZSorterPanel = ISCollapsableWindow:derive("PZSorterPanel")

local function titlePad(window)
    if window.titleBarHeight then
        local ok, height = pcall(function()
            return window:titleBarHeight()
        end)
        if ok and type(height) == "number" then
            return height
        end
    end
    return 16
end

function PZSorterPanel:new(x, y, width, height, player, object)
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self
    window.player = player
    window.object = object
    window.playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
    window.rowWidgets = {}
    window.title = "Sorter"
    if window.setResizable then
        window:setResizable(false)
    end
    return window
end

function PZSorterPanel:record()
    if not self.object or not self.object.getModData then
        return nil
    end
    local modData = self.object:getModData()
    if type(modData) ~= "table" then
        return nil
    end
    local record = modData[Config.MOD_DATA_KEY]
    if type(record) ~= "table" then
        return nil
    end
    return record
end

function PZSorterPanel:position()
    local record = self:record()
    if record and record.x and record.y and record.z then
        return { x = record.x, y = record.y, z = record.z }
    end
    local square = self.object and self.object.getSquare and self.object:getSquare()
    if not square then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

function PZSorterPanel:measure(link)
    local cell = getCell and getCell()
    local square = cell and cell.getGridSquare and cell:getGridSquare(link.x, link.y, link.z)
    if not square then
        return "unloaded", 0, 0, nil
    end
    local row = World.find(square, link.index)
    if not row then
        return "missing", 0, 0, nil
    end
    local weight, capacity = World.weightAndCapacity(row.container)
    local status = Links.status(self:position(), link, Range.current(), true, true)
    return status, weight, capacity, row.object
end

-- Assigned below. signature() runs later, so the local has to exist first.
local filterLine

function PZSorterPanel:signature()
    local record = self:record()
    local links = Links.each(record and record.links)
    local parts = {}
    for i = 1, #links do
        local status, weight, capacity = self:measure(links[i])
        parts[#parts + 1] = table.concat({
            tostring(links[i].x),
            tostring(links[i].y),
            tostring(links[i].z),
            tostring(links[i].index),
            tostring(links[i].name),
            tostring(status),
            tostring(weight),
            tostring(capacity),
            tostring(Links.clampPriority(links[i].priority)),
            filterLine(links[i]),
            self:rowName(links[i]),
        }, ":")
    end
    local recordName = record and record.name or ""
    return recordName .. "|" .. table.concat(parts, "|")
end

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

local function fitText(text, maxChars)
    if type(text) ~= "string" then
        return ""
    end
    if #text <= maxChars then
        return text
    end
    if maxChars < 4 then
        return text:sub(1, maxChars)
    end
    return text:sub(1, maxChars - 3) .. "..."
end

-- The row's one-line filter. A whole category is "Food: 12 items". A few
-- ticked items are "Hammer, Screws". Nothing ticked is "No filter".
function filterLine(link)
    local summary = nil
    if PZSorter.FilterTree and PZSorter.FilterTree.summary and PZSorter.FilterTree.cached then
        local ok, text = pcall(function()
            return PZSorter.FilterTree.summary(link and link.filter, PZSorter.FilterTree.cached())
        end)
        if ok and type(text) == "string" then
            summary = text
        end
    end
    if not summary then
        summary = Filter.summary(link and link.filter)
    end
    if summary == Filter.NONE and getText then
        return getText("IGUI_PZSorter_NoFilter")
    end
    return summary
end

-- Custom name from the container when the player renamed it, otherwise
-- the auto name stored on the link ("Sidetable 1"). Read on each refresh
-- so a rename made while this panel is open shows up on the next tick.
function PZSorterPanel:rowName(link)
    local cell = getCell and getCell()
    local square = cell and cell.getGridSquare and cell:getGridSquare(link.x, link.y, link.z)
    local row = square and World.find(square, link.index)
    return World.containerLabel(link and link.name, row and row.container)
end

local function statusText(status)
    if status == "missing" then
        return getText("IGUI_PZSorter_Missing")
    end
    if status == "range" then
        return getText("IGUI_PZSorter_OutOfRange")
    end
    if status == "unloaded" then
        return getText("IGUI_PZSorter_NotLoaded")
    end
    return getText("IGUI_PZSorter_Ok")
end

local function statusColor(status)
    if status == "missing" then
        return 0.95, 0.25, 0.22
    end
    if status == "ok" then
        return 0.30, 0.85, 0.35
    end
    return 0.55, 0.55, 0.55
end

function PZSorterPanel:showHighlights()
    if not PZSorter.Highlight then
        return
    end
    if self.hoverObject then
        PZSorter.Highlight.show({ self.hoverObject }, self.playerNum)
        return
    end
    local objects = {}
    for i = 1, #(self.rowWidgets or {}) do
        local widget = self.rowWidgets[i]
        if widget.liveObject and widget.status ~= "missing" and widget.status ~= "unloaded" then
            objects[#objects + 1] = widget.liveObject
        end
    end
    PZSorter.Highlight.show(objects, self.playerNum)
end

function PZSorterPanel:clearCustomChildren()
    for i = 1, #(self.rowWidgets or {}) do
        self:removeChild(self.rowWidgets[i])
    end
    self.rowWidgets = {}
    if self.emptyLabel then
        self:removeChild(self.emptyLabel)
        self.emptyLabel = nil
    end
    if self.sortButton then
        self:removeChild(self.sortButton)
        self.sortButton = nil
    end
    if self.previewButton then
        self:removeChild(self.previewButton)
        self.previewButton = nil
    end
end

function PZSorterPanel:sorterArgs()
    local record = self:record()
    local square = self.object and self.object.getSquare and self.object:getSquare()
    if not record or not square then
        return nil
    end
    return {
        sorterId = record.id,
        sorterX = square:getX(),
        sorterY = square:getY(),
        sorterZ = square:getZ(),
    }
end

function PZSorterPanel:changePriority(button, delta)
    local widget = button and button.rowWidget
    local window = widget and widget.parentPanel
    if not window or not widget or not widget.link then
        return
    end
    local current = Links.clampPriority(widget.link.priority)
    local nextPriority = Links.clampPriority(current + delta)
    if nextPriority == current then
        return
    end
    local args = window:sorterArgs()
    if not args then
        print("PZSorter: priority has no sorter")
        return
    end
    args.x = widget.link.x
    args.y = widget.link.y
    args.z = widget.link.z
    args.index = widget.link.index
    args.priority = nextPriority
    print("PZSorter: priority " .. tostring(widget.shownName or widget.link.name) .. " " .. tostring(current) .. " -> " .. tostring(nextPriority))
    request(window.player, "SetPriority", args)
    window._signature = nil
end

function PZSorterPanel:onPriorityUp(button)
    self:changePriority(button, 1)
end

function PZSorterPanel:onPriorityDown(button)
    self:changePriority(button, -1)
end

function PZSorterPanel:onEditFilter(button)
    local widget = button and button.rowWidget
    local window = widget and widget.parentPanel
    if not window or not widget or not widget.link then
        return
    end
    print("PZSorter: edit filter " .. tostring(widget.shownName or widget.link.name))
    if PZSorter.FilterEditor and PZSorter.FilterEditor.open then
        PZSorter.FilterEditor.open(window.player, window.object, widget.link, window)
    elseif PZSorter.FilterChecklist and PZSorter.FilterChecklist.open then
        PZSorter.FilterChecklist.open(window.player, window.object, widget.link, window)
    else
        print("PZSorter: filter editor is not loaded")
    end
end

function PZSorterPanel:onSort()
    print("PZSorter: Sort clicked")
    if PZSorter.SortAction and PZSorter.SortAction.start then
        PZSorter.SortAction.start(self.player, self.object)
    else
        print("PZSorter: sort action is not loaded")
    end
end

function PZSorterPanel:onRemove(button)
    local widget = button and button.rowWidget
    local window = widget and widget.parentPanel
    if not window or not widget or not widget.link then
        return
    end
    local record = window:record()
    local square = window.object and window.object.getSquare and window.object:getSquare()
    if not record or not square then
        print("PZSorter: remove has no sorter")
        return
    end
    print("PZSorter: remove clicked " .. tostring(widget.shownName or widget.link.name))
    local args = {
        sorterId = record.id,
        sorterX = square:getX(),
        sorterY = square:getY(),
        sorterZ = square:getZ(),
        x = widget.link.x,
        y = widget.link.y,
        z = widget.link.z,
        index = widget.link.index,
    }
    request(window.player, "Unassign", args)
    window._signature = nil
end

function PZSorterPanel:rebuildRows()
    self:clearCustomChildren()
    local record = self:record()
    local name = record and record.name or getText("IGUI_PZSorter_DefaultObjectName")
    self.title = name
    local links = Links.each(record and record.links)
    local top = titlePad(self) + 8
    local width = self.width
    if #links == 0 then
        local label = ISLabel:new(12, top, 18, getText("IGUI_PZSorter_NoLinks"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
        label:initialise()
        self:addChild(label)
        self.emptyLabel = label
        top = top + 28
    end
    for i = 1, #links do
        local link = links[i]
        local status, weight, capacity, object = self:measure(link)
        local summary = filterLine(link)
        local shown = self:rowName(link)
        local nameNote = tostring(shown)
        if shown ~= link.name then
            nameNote = tostring(shown) .. " auto=" .. tostring(link.name)
        end
        print("PZSorter: row " .. nameNote
            .. " status=" .. tostring(status)
            .. " weight=" .. tostring(weight) .. "/" .. tostring(capacity)
            .. " priority=" .. tostring(Links.clampPriority(link.priority))
            .. " filter=" .. summary)
        local row = PZSorterLinkRow:new(8, top, width - 16, 70, self, link, status, weight, capacity, object, summary, shown)
        row:initialise()
        self:addChild(row)
        self.rowWidgets[#self.rowWidgets + 1] = row
        top = top + 74
    end
    local sort = ISButton:new(8, top, 90, 22, getText("IGUI_PZSorter_Sort"), self, PZSorterPanel.onSort)
    sort:initialise()
    sort:instantiate()
    sort.enable = true
    if sort.setEnable then
        sort:setEnable(true)
    end
    self:addChild(sort)
    self.sortButton = sort
    local preview = ISButton:new(104, top, 90, 22, getText("IGUI_PZSorter_Preview"), self, function() end)
    preview:initialise()
    preview:instantiate()
    preview.enable = false
    if preview.setEnable then
        preview:setEnable(false)
    end
    self:addChild(preview)
    self.previewButton = preview
    local height = top + 36
    if self.setHeight then
        self:setHeight(height)
    else
        self.height = height
    end
    self._signature = self:signature()
    self.hoverObject = nil
    self:showHighlights()
    print("PZSorter: sorter panel rows=" .. tostring(#links) .. " name=" .. tostring(name))
end

function PZSorterPanel:initialise()
    ISCollapsableWindow.initialise(self)
    self:rebuildRows()
end

function PZSorterPanel:update()
    if ISCollapsableWindow.update then
        ISCollapsableWindow.update(self)
    end
    if not self.object or not self.object.getSquare or not self.object:getSquare() then
        print("PZSorter: sorter panel crate is gone")
        self:close()
        return
    end
    local signature = self:signature()
    if signature ~= self._signature then
        self:rebuildRows()
    end
end

function PZSorterPanel:close()
    print("PZSorter: sorter panel closed")
    if PZSorter.FilterEditor and PZSorter.FilterEditor.close then
        PZSorter.FilterEditor.close()
    elseif PZSorter.FilterChecklist and PZSorter.FilterChecklist.close then
        PZSorter.FilterChecklist.close()
    end
    if PZSorter.Highlight then
        PZSorter.Highlight.clear()
    end
    if PanelApi.current == self then
        PanelApi.current = nil
    end
    ISCollapsableWindow.close(self)
end

PZSorterLinkRow = ISPanel:derive("PZSorterLinkRow")

function PZSorterLinkRow:new(x, y, width, height, parentPanel, link, status, weight, capacity, object, summary, shownName)
    local panel = ISPanel:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.parentPanel = parentPanel
    panel.link = link
    panel.status = status
    panel.weight = weight or 0
    panel.capacity = capacity or 0
    panel.liveObject = object
    panel.summary = summary or ""
    panel.shownName = shownName or (link and link.name) or ""
    panel.backgroundColor = { r = 0.12, g = 0.11, b = 0.09, a = 0.92 }
    panel.borderColor = { r = 0.35, g = 0.3, b = 0.2, a = 1 }
    return panel
end

local function setButtonEnabled(button, enabled)
    button.enable = enabled and true or false
    if button.setEnable then
        button:setEnable(button.enable)
    end
end

function PZSorterLinkRow:initialise()
    ISPanel.initialise(self)
    local priority = Links.clampPriority(self.link.priority)
    local name = ISLabel:new(8, 2, 16, fitText(self.shownName or self.link.name or "", 28), 1, 1, 1, 1, UIFont.Small, true)
    name:initialise()
    self:addChild(name)
    local red, green, blue = statusColor(self.status)
    local statusLabel = ISLabel:new(self.width - 160, 2, 16, statusText(self.status), red, green, blue, 1, UIFont.Small, true)
    statusLabel:initialise()
    self:addChild(statusLabel)

    local noFilter = getText and self.summary == getText("IGUI_PZSorter_NoFilter")
    local fr, fg, fb = 0.86, 0.82, 0.66
    if noFilter then
        fr, fg, fb = 0.78, 0.46, 0.38
    end
    local filterLabel = ISLabel:new(8, 22, 16, fitText(self.summary, 42), fr, fg, fb, 1, UIFont.Small, true)
    filterLabel:initialise()
    self:addChild(filterLabel)

    local priorityLabel = ISLabel:new(self.width - 156, 22, 16, getText("IGUI_PZSorter_Priority"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    priorityLabel:initialise()
    self:addChild(priorityLabel)
    local up = ISButton:new(self.width - 78, 20, 22, 20, getText("IGUI_PZSorter_PriorityUp"), self.parentPanel, PZSorterPanel.onPriorityUp)
    up:initialise()
    up:instantiate()
    up.rowWidget = self
    setButtonEnabled(up, priority < 9)
    self:addChild(up)
    local number = ISLabel:new(self.width - 52, 22, 16, tostring(priority), 1, 1, 1, 1, UIFont.Small, true)
    number:initialise()
    self:addChild(number)
    local down = ISButton:new(self.width - 30, 20, 22, 20, getText("IGUI_PZSorter_PriorityDown"), self.parentPanel, PZSorterPanel.onPriorityDown)
    down:initialise()
    down:instantiate()
    down.rowWidget = self
    setButtonEnabled(down, priority > 1)
    self:addChild(down)

    local edit = ISButton:new(self.width - 200, 46, 108, 20, getText("IGUI_PZSorter_EditFilter"), self.parentPanel, PZSorterPanel.onEditFilter)
    edit:initialise()
    edit:instantiate()
    edit.rowWidget = self
    self:addChild(edit)
    local remove = ISButton:new(self.width - 86, 46, 78, 20, getText("IGUI_PZSorter_Remove"), self.parentPanel, PZSorterPanel.onRemove)
    remove:initialise()
    remove:instantiate()
    remove.rowWidget = self
    self:addChild(remove)
    self.removeButton = remove
end

function PZSorterLinkRow:render()
    ISPanel.render(self)
    local ratio = 0
    if self.capacity > 0 then
        ratio = math.min(1, math.max(0, self.weight / self.capacity))
    end
    self:drawRect(8, 50, 160, 8, 0.85, 0.18, 0.16, 0.13)
    self:drawRect(8, 50, 160 * ratio, 8, 0.95, 0.72, 0.52, 0.16)
    local red, green, blue = statusColor(self.status)
    self:drawRect(176, 48, 10, 10, 1, red, green, blue)
end

function PZSorterLinkRow:onMouseMove(dx, dy)
    local window = self.parentPanel
    if not window then
        return
    end
    window.hoverObject = self.liveObject
    if self.liveObject and PZSorter.Highlight then
        PZSorter.Highlight.show({ self.liveObject }, window.playerNum)
    elseif PZSorter.Highlight then
        PZSorter.Highlight.clear()
    end
end

function PZSorterLinkRow:onMouseMoveOutside(dx, dy)
    local window = self.parentPanel
    if not window then
        return
    end
    if window.hoverObject == self.liveObject then
        window.hoverObject = nil
        window:showHighlights()
    end
end

function PanelApi.open(player, object)
    if PanelApi.current then
        PanelApi.current:close()
    end
    local width = 540
    local height = 160
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local window = PZSorterPanel:new(x, y, width, height, player, object)
    window:initialise()
    window:addToUIManager()
    if window.setVisible then
        window:setVisible(true)
    end
    PanelApi.current = window
    local record = window:record()
    print("PZSorter: sorter panel opened name=" .. tostring(record and record.name))
end

return PanelApi
