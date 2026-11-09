-- Category checklist for one linked container.
--
-- Step 3 ticks whole categories only. The list is the game's inventory
-- display categories (the same names the inventory groups items by), not a
-- list we invented. Allow All ticks every category in that list. Clear All
-- ticks none, which is an empty filter and accepts nothing.
--
-- Item ticks and exclusions are left alone on save. The tree that edits
-- them is a later step, and the filter format already has those fields.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "PZSorter/Config"
require "PZSorter/Filter"

PZSorter = PZSorter or {}
PZSorter.FilterChecklist = PZSorter.FilterChecklist or {}

local Checklist = PZSorter.FilterChecklist

if Checklist._loaded then
    return Checklist
end
Checklist._loaded = true

local Config = PZSorter.Config
local Filter = PZSorter.Filter

-- Used only when the game's item list cannot be read. These are the
-- display category ids from the inventory translation, not the Java enum
-- names. A real session replaces this with whatever getDisplayCategory
-- returns, so items from other mods show up too.
local FALLBACK = {
    "Accessory", "Ammo", "Appearance", "Bag", "Bandage", "Camping",
    "Cartography", "Clothing", "Communications", "Container", "Cooking",
    "Electronics", "Entertainment", "Explosives", "FirstAid", "Fishing",
    "Food", "Furniture", "Gardening", "Household", "Instrument", "Junk",
    "LightSource", "Literature", "Material", "Paint", "Security",
    "SkillBook", "Sports", "Tool", "ToolWeapon", "Trapping",
    "VehicleMaintenance", "Water", "WaterContainer", "Weapon",
    "WeaponCrafted", "WeaponPart",
}

local cachedLabels = nil

local function asText(value)
    if type(value) == "string" then
        if value == "" then
            return nil
        end
        return value
    end
    if value and type(value.toString) == "function" then
        local ok, text = pcall(value.toString, value)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    return nil
end

local function labelFor(id)
    if getText then
        local key = "IGUI_ItemCat_" .. id
        local text = getText(key)
        if type(text) == "string" and text ~= "" and text ~= key then
            return text
        end
    end
    return id
end

local function gather()
    local found = {}
    local sawGame = false
    pcall(function()
        local manager = nil
        if getScriptManager then
            manager = getScriptManager()
        end
        if (not manager or not manager.getAllItems) and ScriptManager and ScriptManager.instance then
            manager = ScriptManager.instance
        end
        if not manager or not manager.getAllItems then
            return
        end
        local all = manager:getAllItems()
        if not all or not all.size or not all.get then
            return
        end
        for i = 0, all:size() - 1 do
            local script = all:get(i)
            if script and script.getDisplayCategory then
                local name = asText(script:getDisplayCategory())
                -- Hidden is a real category, but the inventory does not
                -- show it, so it is not something a player can filter by.
                if name and name ~= "Hidden" then
                    found[name] = true
                    sawGame = true
                end
            end
        end
    end)
    local list = {}
    if sawGame then
        for name in pairs(found) do
            list[#list + 1] = name
        end
    else
        for i = 1, #FALLBACK do
            list[i] = FALLBACK[i]
        end
    end
    table.sort(list, function(a, b)
        return labelFor(a):lower() < labelFor(b):lower()
    end)
    local source = sawGame and "game" or "fallback"
    print("PZSorter: filter categories=" .. tostring(#list) .. " source=" .. source)
    return list, source
end

function Checklist.labels()
    if cachedLabels then
        return cachedLabels
    end
    local list = gather()
    local labels = {}
    for i = 1, #list do
        labels[list[i]] = labelFor(list[i])
    end
    cachedLabels = labels
    return labels
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

if not ISCollapsableWindow or not ISScrollingListBox then
    print("PZSorter: filter checklist ui missing")
    return Checklist
end

PZSorterFilterWindow = ISCollapsableWindow:derive("PZSorterFilterWindow")

function PZSorterFilterWindow:new(x, y, width, height, player, object, link, panel)
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self
    window.player = player
    window.object = object
    window.link = link
    window.parentPanel = panel
    window._saved = false
    window._closing = false
    local name = link and link.name or "Container"
    window.title = getText and getText("IGUI_PZSorter_FilterTitle", name) or name
    if window.setResizable then
        window:setResizable(false)
    end
    return window
end

function PZSorterFilterWindow:setAll(ticked)
    local items = self.list and self.list.items or {}
    for i = 1, #items do
        if items[i].item then
            items[i].item.ticked = ticked and true or false
        end
    end
    if ticked then
        print("PZSorter: filter allow all " .. tostring(self.link and self.link.name))
    else
        print("PZSorter: filter clear all " .. tostring(self.link and self.link.name))
    end
end

function PZSorterFilterWindow:writeFilter()
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
    local names = {}
    local items = self.list and self.list.items or {}
    for i = 1, #items do
        local data = items[i].item
        if data and data.ticked and type(data.id) == "string" then
            names[#names + 1] = data.id
        end
    end
    -- The server writes the filter. Doing it here as well would keep a
    -- change the server refused (the player walked off) on the crate.
    local summary = Filter.summary(Filter.withCategories(link.filter, names), Checklist.labels())
    if summary == Filter.NONE and getText then
        summary = getText("IGUI_PZSorter_NoFilter")
    end
    print("PZSorter: filter " .. tostring(link.name) .. " " .. summary)
    request(self.player, "SetFilter", {
        sorterId = record.id,
        sorterX = square:getX(),
        sorterY = square:getY(),
        sorterZ = square:getZ(),
        x = link.x,
        y = link.y,
        z = link.z,
        index = link.index,
        categoriesText = table.concat(names, "\n"),
    })
    if self.parentPanel then
        self.parentPanel._signature = nil
    end
end

function PZSorterFilterWindow:initialise()
    ISCollapsableWindow.initialise(self)
    cachedLabels = nil
    local categories = gather()
    local ticked = {}
    local selected = Filter.categoryNames(self.link and self.link.filter)
    for i = 1, #selected do
        ticked[selected[i]] = true
    end
    local list = ISScrollingListBox:new(12, 28, self.width - 24, self.height - 80)
    list:initialise()
    list:instantiate()
    list.itemheight = 22
    list.drawBorder = true
    function list:doDrawItem(y, entry, alt)
        if not entry then
            return y + self.itemheight
        end
        local data = entry.item or {}
        local selectedRow = self.selected
        if selectedRow and (selectedRow == entry.index or selectedRow == entry.itemindex) then
            self:drawRect(0, y, self.width, self.itemheight - 1, 0.28, 0.55, 0.42, 0.16)
        end
        self:drawRectBorder(4, y + 4, 14, 14, 1, 0.86, 0.86, 0.86)
        if data.ticked then
            self:drawRect(6, y + 6, 10, 10, 1, 0.86, 0.68, 0.22)
        end
        local font = UIFont and UIFont.Small or nil
        self:drawText(data.label or entry.text or "", 24, y + 3, 1, 1, 1, 1, font)
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
        if entry and entry.item then
            entry.item.ticked = not entry.item.ticked
            print("PZSorter: filter tick " .. tostring(entry.item.id) .. "=" .. tostring(entry.item.ticked))
        end
    end
    for i = 1, #categories do
        local id = categories[i]
        list:addItem(labelFor(id), {
            id = id,
            label = labelFor(id),
            ticked = ticked[id] and true or false,
        })
    end
    self:addChild(list)
    self.list = list
    local buttonY = self.height - 40
    local allow = ISButton:new(12, buttonY, 110, 22, getText("IGUI_PZSorter_AllowAll"), self, function(target)
        target:setAll(true)
    end)
    allow:initialise()
    allow:instantiate()
    self:addChild(allow)
    local clear = ISButton:new(128, buttonY, 110, 22, getText("IGUI_PZSorter_ClearAll"), self, function(target)
        target:setAll(false)
    end)
    clear:initialise()
    clear:instantiate()
    self:addChild(clear)
    local done = ISButton:new(self.width - 92, buttonY, 80, 22, getText("IGUI_PZSorter_FilterDone"), self, function(target)
        target:close()
    end)
    done:initialise()
    done:instantiate()
    self:addChild(done)
end

function PZSorterFilterWindow:close()
    if self._closing then
        return
    end
    self._closing = true
    if not self._saved then
        self._saved = true
        self:writeFilter()
    end
    if Checklist.current == self then
        Checklist.current = nil
    end
    ISCollapsableWindow.close(self)
end

function Checklist.open(player, object, link, panel)
    if not link then
        print("PZSorter: filter editor has no row")
        return
    end
    if Checklist.current and Checklist.current.close then
        Checklist.current:close()
    end
    local width = 380
    local height = 460
    local screenW = 800
    local screenH = 600
    if getCore and getCore().getScreenWidth then
        screenW = getCore():getScreenWidth()
        screenH = getCore():getScreenHeight()
    end
    local window = PZSorterFilterWindow:new((screenW - width) / 2, (screenH - height) / 2, width, height, player, object, link, panel)
    window:initialise()
    window:addToUIManager()
    if window.setVisible then
        window:setVisible(true)
    end
    if window.bringToTop then
        window:bringToTop()
    end
    Checklist.current = window
    print("PZSorter: filter editor " .. tostring(link.name))
end

function Checklist.close()
    if Checklist.current and Checklist.current.close then
        Checklist.current:close()
    end
end

print("PZSorter: filter checklist loaded (0.3.0)")

return Checklist
