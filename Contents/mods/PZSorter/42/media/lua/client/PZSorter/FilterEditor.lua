-- The filter tree for one linked container.
--
-- Categories expand to their items. Food also expands to Perishable,
-- Frozen, and Non-perishable. A category with only some of its items
-- ticked shows a partial mark. Search hides rows that do not match.
-- Allow All and Clear All tick every category or none. Copy from contents
-- ticks the item types already in the container, and nothing else.
--
-- The server writes the save. This window only sends the three lists.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "PZSorter/Config"
require "PZSorter/Filter"
require "PZSorter/FilterTree"
require "PZSorter/WorldContainers"

PZSorter = PZSorter or {}
PZSorter.FilterEditor = PZSorter.FilterEditor or {}

local Editor = PZSorter.FilterEditor

if Editor._loaded then
    return Editor
end
Editor._loaded = true

local Config = PZSorter.Config
local Filter = PZSorter.Filter
local Tree = PZSorter.FilterTree
local World = PZSorter.WorldContainers

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

local function shownName(link)
    if type(link) ~= "table" then
        return "Container"
    end
    local container = nil
    if getCell and World and World.find then
        local cell = getCell()
        local square = cell and cell.getGridSquare and cell:getGridSquare(link.x, link.y, link.z)
        local row = square and World.find(square, link.index)
        container = row and row.container
    end
    if World and World.containerLabel then
        return World.containerLabel(link.name, container)
    end
    return link.name or "Container"
end

local function linesOf(set)
    local names = {}
    if type(set) ~= "table" then
        return ""
    end
    for name, on in pairs(set) do
        if on and type(name) == "string" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    if #names == 0 then
        -- A blank string can be dropped on the way to the server, and the
        -- server would then keep the old item ticks. A newline is a real
        -- value and parseList turns it into an empty list.
        return "\n"
    end
    return table.concat(names, "\n")
end

local function contentsTypes(link)
    if type(link) ~= "table" or not getCell or not World or not World.find then
        print("PZSorter: filter copy has no container")
        return nil
    end
    local cell = getCell()
    local square = cell and cell.getGridSquare and cell:getGridSquare(link.x, link.y, link.z)
    local row = square and World.find(square, link.index)
    local container = row and row.container
    if not container or type(container.getItems) ~= "function" then
        print("PZSorter: filter copy has no container")
        return nil
    end
    local ok, items = pcall(container.getItems, container)
    if not ok or not items or type(items.size) ~= "function" or type(items.get) ~= "function" then
        print("PZSorter: filter copy could not read the container")
        return nil
    end
    local types = {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local facts = Tree.factsFromObject(item)
            if type(facts.fullType) == "string" then
                types[#types + 1] = facts.fullType
            end
        end
    end
    return types
end

if not ISCollapsableWindow or not ISScrollingListBox then
    print("PZSorter: filter editor ui missing")
    return Editor
end

PZSorterFilterEditor = ISCollapsableWindow:derive("PZSorterFilterEditor")

function PZSorterFilterEditor:new(x, y, width, height, player, object, link, panel)
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self
    window.player = player
    window.object = object
    window.link = link
    window.parentPanel = panel
    window.expanded = {}
    window.query = ""
    window.filter = Filter.normalize(link and link.filter)
    window.tree = Tree.cached()
    window._saved = false
    window._closing = false
    local name = shownName(link)
    window.shownName = name
    window.title = getText and getText("IGUI_PZSorter_FilterTitle", name) or name
    if window.setResizable then
        window:setResizable(false)
    end
    return window
end

function PZSorterFilterEditor:refill()
    local list = self.list
    if not list then
        return
    end
    if list.clear then
        list:clear()
    else
        list.items = {}
    end
    local rows = Tree.rows(self.tree, self.filter, self.query, self.expanded)
    for i = 1, #rows do
        list:addItem(rows[i].label, rows[i])
    end
end

function PZSorterFilterEditor:toggleExpand(id)
    self.expanded[id] = not self.expanded[id]
    print("PZSorter: filter expand " .. tostring(id) .. "=" .. tostring(self.expanded[id] and true or false))
    self:refill()
end

function PZSorterFilterEditor:toggleRow(data)
    if not data or type(data.id) ~= "string" then
        return
    end
    if data.kind == "item" then
        local on = Tree.itemAccepted(self.filter, self.tree, data.id)
        self.filter = Tree.setItem(self.filter, self.tree, data.id, not on)
        print("PZSorter: filter tick " .. data.id .. "=" .. tostring(not on))
    else
        local mark = Tree.mark(self.filter, self.tree, data.id)
        local turnOn = mark ~= Tree.ON
        self.filter = Tree.setCategory(self.filter, self.tree, data.id, turnOn)
        print("PZSorter: filter tick " .. data.id .. "=" .. (turnOn and "on" or "off"))
    end
    self:refill()
end

function PZSorterFilterEditor:writeFilter()
    local link = self.link
    local object = self.object
    if not link or not object or not object.getSquare or not object.getModData then
        print("PZSorter: filter save has no container")
        return
    end
    local square = object:getSquare()
    local modData = object:getModData()
    local record = modData and modData[Config.MOD_DATA_KEY]
    if not square or type(record) ~= "table" then
        print("PZSorter: filter save has no sorter")
        return
    end
    local summary = Tree.summary(self.filter, self.tree)
    if summary == Filter.NONE and getText then
        summary = getText("IGUI_PZSorter_NoFilter")
    end
    print("PZSorter: filter " .. tostring(self.shownName) .. " " .. summary)
    request(self.player, "SetFilter", {
        sorterId = record.id,
        sorterX = square:getX(),
        sorterY = square:getY(),
        sorterZ = square:getZ(),
        x = link.x,
        y = link.y,
        z = link.z,
        index = link.index,
        categoriesText = linesOf(self.filter.categories),
        itemsText = linesOf(self.filter.items),
        excludedText = linesOf(self.filter.excluded),
    })
    if self.parentPanel then
        self.parentPanel._signature = nil
    end
end

function PZSorterFilterEditor:initialise()
    ISCollapsableWindow.initialise(self)
    local searchLabel = ISLabel:new(12, 22, 18, getText("IGUI_PZSorter_Search"), 0.85, 0.85, 0.85, 1, UIFont.Small, true)
    searchLabel:initialise()
    self:addChild(searchLabel)
    local search = ISTextEntryBox:new("", 70, 20, self.width - 84, 20)
    search:initialise()
    search:instantiate()
    self:addChild(search)
    self.search = search

    local list = ISScrollingListBox:new(12, 48, self.width - 24, self.height - 118)
    list:initialise()
    list:instantiate()
    list.itemheight = 22
    list.drawBorder = true
    list.filterWindow = self
    function list:doDrawItem(y, entry, alt)
        if not entry then
            return y + self.itemheight
        end
        local data = entry.item or {}
        local depth = data.depth or 0
        local indent = depth * 14
        local selectedRow = self.selected
        if selectedRow and (selectedRow == entry.index or selectedRow == entry.itemindex) then
            self:drawRect(0, y, self.width, self.itemheight - 1, 0.28, 0.55, 0.42, 0.16)
        end
        if data.kind ~= "item" then
            local arrow = "+"
            local window = self.filterWindow
            if window and window.expanded and window.expanded[data.id] then
                arrow = "-"
            end
            if window and window.query and window.query ~= "" then
                arrow = "-"
            end
            self:drawText(arrow, indent + 2, y + 3, 0.9, 0.8, 0.4, 1, UIFont and UIFont.Small or nil)
        end
        local boxX = indent + 16
        self:drawRectBorder(boxX, y + 4, 14, 14, 1, 0.86, 0.86, 0.86)
        if data.mark == "on" then
            self:drawRect(boxX + 2, y + 6, 10, 10, 1, 0.86, 0.68, 0.22)
        elseif data.mark == "partial" then
            self:drawRect(boxX + 3, y + 9, 8, 3, 1, 0.86, 0.68, 0.22)
        end
        self:drawText(data.label or entry.text or "", boxX + 20, y + 3, 1, 1, 1, 1, UIFont and UIFont.Small or nil)
        return y + self.itemheight
    end
    function list:onMouseDown(x, y)
        if ISScrollingListBox.onMouseDown then
            ISScrollingListBox.onMouseDown(self, x, y)
        end
        local row = self.selected
        if (type(row) ~= "number" or row < 1) and self.rowAt then
            row = self:rowAt(x, y)
        end
        local entry = row and self.items and self.items[row]
        local window = self.filterWindow
        if not window or not entry or not entry.item then
            return
        end
        local data = entry.item
        local indent = (data.depth or 0) * 14
        if data.kind ~= "item" and x < indent + 16 then
            window:toggleExpand(data.id)
        else
            window:toggleRow(data)
        end
    end
    self:addChild(list)
    self.list = list
    self:refill()

    local buttonY = self.height - 62
    local allow = ISButton:new(12, buttonY, 100, 22, getText("IGUI_PZSorter_AllowAll"), self, function(target)
        target.filter = Tree.allowAll(target.tree)
        print("PZSorter: filter allow all " .. tostring(target.shownName))
        target:refill()
    end)
    allow:initialise()
    allow:instantiate()
    self:addChild(allow)
    local clear = ISButton:new(118, buttonY, 100, 22, getText("IGUI_PZSorter_ClearAll"), self, function(target)
        target.filter = Tree.clearAll()
        print("PZSorter: filter clear all " .. tostring(target.shownName))
        target:refill()
    end)
    clear:initialise()
    clear:instantiate()
    self:addChild(clear)
    local copy = ISButton:new(224, buttonY, 150, 22, getText("IGUI_PZSorter_CopyFromContents"), self, function(target)
        local types = contentsTypes(target.link)
        if not types then
            return
        end
        target.filter = Tree.fromContents(types)
        local count = 0
        for _ in pairs(target.filter.items) do
            count = count + 1
        end
        print("PZSorter: filter copy from contents " .. tostring(target.shownName) .. " types=" .. tostring(count))
        target:refill()
    end)
    copy:initialise()
    copy:instantiate()
    self:addChild(copy)
    local done = ISButton:new(self.width - 92, self.height - 32, 80, 22, getText("IGUI_PZSorter_FilterDone"), self, function(target)
        target:close()
    end)
    done:initialise()
    done:instantiate()
    self:addChild(done)
end

function PZSorterFilterEditor:update()
    if ISCollapsableWindow.update then
        ISCollapsableWindow.update(self)
    end
    local text = ""
    if self.search and self.search.getText then
        text = self.search:getText() or ""
    end
    if text ~= self.query then
        self.query = text
        print("PZSorter: filter search " .. text)
        self:refill()
    end
end

function PZSorterFilterEditor:close()
    if self._closing then
        return
    end
    self._closing = true
    if not self._saved then
        self._saved = true
        self:writeFilter()
    end
    if Editor.current == self then
        Editor.current = nil
    end
    ISCollapsableWindow.close(self)
end

function Editor.open(player, object, link, panel)
    if not link then
        print("PZSorter: filter editor has no row")
        return
    end
    if Editor.current and Editor.current.close then
        Editor.current:close()
    end
    local width = 440
    local height = 520
    local screenW = 800
    local screenH = 600
    if getCore and getCore().getScreenWidth then
        screenW = getCore():getScreenWidth()
        screenH = getCore():getScreenHeight()
    end
    local window = PZSorterFilterEditor:new((screenW - width) / 2, (screenH - height) / 2, width, height, player, object, link, panel)
    window:initialise()
    window:addToUIManager()
    if window.setVisible then
        window:setVisible(true)
    end
    if window.bringToTop then
        window:bringToTop()
    end
    Editor.current = window
    print("PZSorter: filter editor " .. tostring(window.shownName))
end

function Editor.close()
    if Editor.current and Editor.current.close then
        Editor.current:close()
    end
end

print("PZSorter: filter editor loaded (0.4.0)")

return Editor
