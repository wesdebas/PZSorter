-- "Assign to Sorter" on a container, and "Open Sorter" / "Sort" on the crate.
--
-- The submenu lists sorters we know about that are near this tile. One
-- that is inside the sandbox square can be chosen. One that is near but
-- outside that square is grey, with "Too far from [Name]". A container
-- that already belongs to a sorter offers Move and Unassign instead of a
-- second Assign.

require "ISUI/ISContextMenu"
require "PZSorter/Config"
require "PZSorter/Range"
require "PZSorter/Links"
require "PZSorter/WorldContainers"

PZSorter = PZSorter or {}
PZSorter.ContextMenu = PZSorter.ContextMenu or {}

local Menu = PZSorter.ContextMenu
local Config = PZSorter.Config
local Range = PZSorter.Range
local Links = PZSorter.Links
local World = PZSorter.WorldContainers

if Menu._hooked then
    return Menu
end
Menu._hooked = true

local function squareOf(worldobjects)
    if not worldobjects then
        return nil
    end
    local function fromObject(object)
        if object and object.getSquare then
            return object:getSquare()
        end
        return nil
    end
    if worldobjects.size and worldobjects.get then
        for i = 0, worldobjects:size() - 1 do
            local square = fromObject(worldobjects:get(i))
            if square then
                return square
            end
        end
        return nil
    end
    if type(worldobjects) == "table" then
        for _, object in ipairs(worldobjects) do
            local square = fromObject(object)
            if square then
                return square
            end
        end
    end
    return nil
end

local function findSorterObject(worldobjects)
    local function check(object)
        if not object or not object.getSprite then
            return nil
        end
        local sprite = object:getSprite()
        local name = sprite and sprite.getName and sprite:getName()
        if Config.isSorterSpriteName(name) then
            return object
        end
        return nil
    end
    if worldobjects and worldobjects.size and worldobjects.get then
        for i = 0, worldobjects:size() - 1 do
            local found = check(worldobjects:get(i))
            if found then
                return found
            end
        end
    elseif type(worldobjects) == "table" then
        for _, object in ipairs(worldobjects) do
            local found = check(object)
            if found then
                return found
            end
        end
    end
    return nil
end

local function knownSorters()
    local list = {}
    if not ModData or not ModData.getOrCreate then
        print("PZSorter: no world list, assign menu is empty")
        return list
    end
    local world = ModData.getOrCreate(Config.MOD_DATA_KEY)
    local sorters = world and world.sorters
    if type(sorters) ~= "table" then
        return list
    end
    for _, saved in pairs(sorters) do
        if type(saved) == "table" and not saved.gone and saved.id ~= nil and saved.x and saved.y and saved.z then
            list[#list + 1] = saved
        end
    end
    return list
end

local function rowLabel(row, rows)
    local kind = Links.typeLabel(World.containerType(row.container))
    local same = 0
    local which = 1
    for i = 1, #rows do
        if Links.typeLabel(World.containerType(rows[i].container)) == kind then
            same = same + 1
            if rows[i].index == row.index then
                which = same
            end
        end
    end
    if same > 1 then
        return kind .. " " .. tostring(which)
    end
    return kind
end

local function greyOut(option, text)
    option.notAvailable = true
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip.description = text
        option.toolTip = tip
    end
end

local function request(player, command, args)
    if PZSorter.Commands and PZSorter.Commands.request then
        PZSorter.Commands.request(player, command, args)
        return
    end
    -- Multiplayer client: the server file is not loaded here. The send is
    -- what reaches Commands.lua on the server.
    if sendClientCommand then
        print("PZSorter: command sent " .. tostring(command))
        sendClientCommand(player, Config.COMMAND_MODULE, command, args)
        return
    end
    print("PZSorter: no way to run " .. tostring(command))
end

local function onPick(player, payload)
    print("PZSorter: chose " .. tostring(payload.command) .. " for sorter " .. tostring(payload.args.sorterId))
    request(player, payload.command, payload.args)
end

local function commandName(action)
    if action == "move" then
        return "Move"
    end
    if action == "unassign" then
        return "Unassign"
    end
    return "Assign"
end

local function entryLabel(entry)
    if entry.action == "unassign" then
        return getText("IGUI_PZSorter_Unassign", entry.name)
    end
    if entry.action == "move" then
        return getText("IGUI_PZSorter_MoveTo", entry.name)
    end
    return entry.name
end

local function fillChoices(menu, player, row)
    local square = row.object and row.object.getSquare and row.object:getSquare()
    if not square then
        print("PZSorter: assign menu container has no square")
        return
    end
    local target = { x = square:getX(), y = square:getY(), z = square:getZ() }
    local ownerId = World.readSorterId(row)
    local entries = Links.menuEntries(knownSorters(), target, Range.current(), ownerId)
    print("PZSorter: assign menu index=" .. tostring(row.index) .. " choices=" .. tostring(#entries) .. " owner=" .. tostring(ownerId))
    if #entries == 0 then
        local none = menu:addOption(getText("IGUI_PZSorter_NoSorters"), nil, nil)
        greyOut(none, getText("IGUI_PZSorter_NoSorters"))
        return
    end
    for i = 1, #entries do
        local entry = entries[i]
        local args = {
            sorterId = entry.id,
            sorterX = entry.x,
            sorterY = entry.y,
            sorterZ = entry.z,
            x = target.x,
            y = target.y,
            z = target.z,
            index = row.index,
        }
        local option = menu:addOption(entryLabel(entry), player, onPick, {
            command = commandName(entry.action),
            args = args,
        })
        if not entry.enabled then
            greyOut(option, getText("IGUI_PZSorter_TooFar", entry.name))
        end
    end
end

local function openPanel(player, object)
    print("PZSorter: Open Sorter clicked")
    if PZSorter.SorterPanel and PZSorter.SorterPanel.open then
        PZSorter.SorterPanel.open(player, object)
    else
        print("PZSorter: sorter panel is not loaded")
    end
end

local function onSort(player, object)
    print("PZSorter: Sort clicked from the menu")
    if PZSorter.SortAction and PZSorter.SortAction.start then
        PZSorter.SortAction.start(player, object)
    else
        print("PZSorter: sort action is not loaded")
    end
end

local function onFillMenu(playerNum, context, worldobjects, test)
    local ok, err = pcall(function()
        if not context or not context.addOption then
            return
        end
        local player = getSpecificPlayer(playerNum)
        local sorterObject = findSorterObject(worldobjects)
        if sorterObject then
            context:addOption(getText("IGUI_PZSorter_Open"), player, openPanel, sorterObject)
            context:addOption(getText("IGUI_PZSorter_Sort"), player, onSort, sorterObject)
        end
        local square = squareOf(worldobjects)
        if not square then
            return
        end
        local rows = World.list(square)
        local assignable = {}
        for i = 1, #rows do
            local info = World.describe(rows[i], player)
            if not Links.exclusion(info) then
                assignable[#assignable + 1] = rows[i]
            end
        end
        if #assignable == 0 then
            return
        end
        print("PZSorter: assign menu containers=" .. tostring(#assignable))
        if not ISContextMenu or not ISContextMenu.getNew then
            print("PZSorter: ISContextMenu has no submenu")
            return
        end
        local parent = context:addOption(getText("IGUI_PZSorter_Assign"), nil, nil)
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(parent, sub)
        if #assignable == 1 then
            fillChoices(sub, player, assignable[1])
        else
            for i = 1, #assignable do
                local row = assignable[i]
                local nestedOption = sub:addOption(rowLabel(row, assignable), nil, nil)
                local nested = ISContextMenu:getNew(sub)
                sub:addSubMenu(nestedOption, nested)
                fillChoices(nested, player, row)
            end
        end
        if test then
            return
        end
    end)
    if not ok then
        print("PZSorter: assign menu failed: " .. tostring(err))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)

print("PZSorter: assign menu loaded (0.3.0)")

return Menu
