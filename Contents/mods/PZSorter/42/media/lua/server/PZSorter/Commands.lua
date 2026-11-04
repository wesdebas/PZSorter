-- Assign, move, and unassign. The server is the side that writes the save.
--
-- The client sends these with sendClientCommand. On a dedicated server,
-- OnClientCommand lands here. In single player, isClient() and isServer()
-- are both false, and that send never arrives, so the menu calls the same
-- handler directly. Either way there is one function that changes the link.

require "PZSorter/Config"
require "PZSorter/Range"
require "PZSorter/Links"
require "PZSorter/WorldContainers"
require "PZSorter/Access"
require "PZSorter/SorterData"

PZSorter = PZSorter or {}
PZSorter.Commands = PZSorter.Commands or {}

local Commands = PZSorter.Commands
local Config = PZSorter.Config
local Range = PZSorter.Range
local Links = PZSorter.Links
local World = PZSorter.WorldContainers
local Access = PZSorter.Access
local Data = PZSorter.SorterData

if Commands._hooked then
    return Commands
end
Commands._hooked = true

-- Right-click reach, in tiles. The container can be up to the sandbox
-- range from the sorter. The player still has to be standing at the thing
-- they clicked, which is a few tiles, not the whole sorter range.
local REACH = 3

local function worldTable()
    if Data and Data.getWorld then
        return Data.getWorld()
    end
    return ModData.getOrCreate(Config.MOD_DATA_KEY)
end

local function halo(player, key)
    if player and player.setHaloNote and getText then
        pcall(function()
            player:setHaloNote(getText(key))
        end)
    end
end

local function squareAt(x, y, z)
    local cell = getCell and getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end
    return cell:getGridSquare(x, y, z)
end

local function near(player, x, y, z)
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)
    if not x or not y or not z then
        return false
    end
    if not player or not player.getSquare then
        return false
    end
    local square = player:getSquare()
    if not square then
        return false
    end
    if math.abs(square:getZ() - z) > Range.FLOOR_SPAN then
        return false
    end
    return Range.chebyshev(square:getX(), square:getY(), x, y) <= REACH
end

local function recordOf(object)
    if not object or not object.getModData then
        return nil
    end
    local modData = object:getModData()
    if type(modData) ~= "table" then
        return nil
    end
    local record = modData[Config.MOD_DATA_KEY]
    if type(record) ~= "table" or record.id == nil then
        return nil
    end
    return record
end

local function findSorter(id, x, y, z)
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)
    if not x or not y or not z then
        return nil, nil
    end
    local square = squareAt(x, y, z)
    if not square or not square.getObjects then
        return nil, nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Data.isSorterObject(object) then
            local record = recordOf(object)
            if record and (id == nil or tostring(record.id) == tostring(id)) then
                return object, record
            end
        end
    end
    return nil, nil
end

local function livingRecord(id)
    local world = worldTable()
    local saved = world and world.sorters and world.sorters[tostring(id)]
    if type(saved) == "table" and not saved.gone then
        return saved
    end
    return nil
end

local function transmit(object)
    if object and object.transmitModData then
        pcall(function()
            object:transmitModData()
        end)
    end
end

local function spotOf(args)
    if type(args) ~= "table" then
        return nil
    end
    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    local index = tonumber(args.index)
    if not x or not y or not z or not index then
        return nil
    end
    return { x = x, y = y, z = z, index = index }
end

-- Drop a sorter id that points at a crate we already dismantled, so the
-- container can be assigned again.
-- A dismantled sorter is stored as gone. The container still saying that
-- id would block a new assignment forever. An id we have simply never
-- heard of is left alone: the crate's world entry may not be loaded yet,
-- and Unassign still clears it.
local function clearStaleOwner(row)
    local ownerId = World.readSorterId(row)
    if ownerId == nil then
        return nil
    end
    local world = worldTable()
    local saved = world and world.sorters and world.sorters[tostring(ownerId)]
    if type(saved) == "table" and saved.gone then
        print("PZSorter: clearing stale sorter id " .. tostring(ownerId))
        World.writeSorterId(row, nil)
        return nil
    end
    return ownerId
end

local function allowedSquares(player, squares)
    for i = 1, #squares do
        local square = squares[i]
        if square and not Access.allowed(player, square) then
            halo(player, "IGUI_PZSorter_Safehouse")
            return false
        end
    end
    return true
end

local function reject(reason)
    print("PZSorter: link refused, " .. reason)
    return false
end

function Commands.releaseSorter(record)
    if type(record) ~= "table" then
        return
    end
    local links = PZSorter.Links.each(record.links)
    for i = 1, #links do
        local link = links[i]
        local square = squareAt(link.x, link.y, link.z)
        local row = square and World.find(square, link.index)
        if row then
            local ownerId = World.readSorterId(row)
            if ownerId == nil or tostring(ownerId) == tostring(record.id) then
                World.writeSorterId(row, nil)
            end
        end
    end
    record.links = {}
end

function Commands.assign(player, args)
    print("PZSorter: assign entered")
    local spot = spotOf(args)
    if not spot then
        return reject("bad arguments")
    end
    if not near(player, spot.x, spot.y, spot.z) then
        return reject("player is not next to the container")
    end
    local containerSquare = squareAt(spot.x, spot.y, spot.z)
    if not containerSquare then
        return reject("container square is not loaded")
    end
    local sorterObject, record = findSorter(args.sorterId, tonumber(args.sorterX), tonumber(args.sorterY), tonumber(args.sorterZ))
    if not record then
        return reject("sorter was not found")
    end
    local sorterSquare = sorterObject:getSquare()
    if not allowedSquares(player, { containerSquare, sorterSquare }) then
        return false
    end
    if not Range.isInRange(
        { x = record.x, y = record.y, z = record.z },
        spot,
        Range.current()
    ) then
        return reject("outside sorter range")
    end
    local row = World.find(containerSquare, spot.index)
    if not row then
        return reject("no container at index " .. tostring(spot.index))
    end
    local excluded = PZSorter.Links.exclusion(World.describe(row, player))
    if excluded then
        return reject("excluded " .. excluded)
    end
    local ownerId = clearStaleOwner(row)
    local link, reason = Links.add(record, spot, World.containerType(row.container), ownerId)
    if not link then
        return reject(tostring(reason))
    end
    World.writeSorterId(row, record.id)
    transmit(sorterObject)
    print("PZSorter: assigned " .. tostring(link.name) .. " to " .. tostring(record.name) .. " id=" .. tostring(record.id))
    return true
end

function Commands.move(player, args)
    print("PZSorter: move entered")
    local spot = spotOf(args)
    if not spot then
        return reject("bad arguments")
    end
    if not near(player, spot.x, spot.y, spot.z) then
        return reject("player is not next to the container")
    end
    local containerSquare = squareAt(spot.x, spot.y, spot.z)
    if not containerSquare then
        return reject("container square is not loaded")
    end
    local sorterObject, record = findSorter(args.sorterId, tonumber(args.sorterX), tonumber(args.sorterY), tonumber(args.sorterZ))
    if not record then
        return reject("sorter was not found")
    end
    local sorterSquare = sorterObject:getSquare()
    if not allowedSquares(player, { containerSquare, sorterSquare }) then
        return false
    end
    if not Range.isInRange(
        { x = record.x, y = record.y, z = record.z },
        spot,
        Range.current()
    ) then
        return reject("outside sorter range")
    end
    local row = World.find(containerSquare, spot.index)
    if not row then
        return reject("no container at index " .. tostring(spot.index))
    end
    local excluded = PZSorter.Links.exclusion(World.describe(row, player))
    if excluded then
        return reject("excluded " .. excluded)
    end
    local ownerId = clearStaleOwner(row)
    if ownerId == nil or tostring(ownerId) == tostring(record.id) then
        if tostring(ownerId) == tostring(record.id) then
            print("PZSorter: move left the container on " .. tostring(record.name))
            return true
        end
        local link, reason = Links.add(record, spot, World.containerType(row.container), nil)
        if not link then
            return reject(tostring(reason))
        end
        World.writeSorterId(row, record.id)
        transmit(sorterObject)
        print("PZSorter: move had no previous sorter, assigned " .. tostring(link.name))
        return true
    end
    local fromSaved = livingRecord(ownerId)
    local fromObject, fromRecord = nil, nil
    if fromSaved then
        fromObject, fromRecord = findSorter(ownerId, fromSaved.x, fromSaved.y, fromSaved.z)
    end
    if not fromRecord then
        print("PZSorter: move could not load the old sorter, assigning fresh")
        World.writeSorterId(row, nil)
        local link, reason = Links.add(record, spot, World.containerType(row.container), nil)
        if not link then
            return reject(tostring(reason))
        end
        World.writeSorterId(row, record.id)
        transmit(sorterObject)
        return true
    end
    local link, reason = Links.move(fromRecord, record, spot, World.containerType(row.container))
    if not link then
        return reject(tostring(reason))
    end
    World.writeSorterId(row, record.id)
    transmit(fromObject)
    transmit(sorterObject)
    print("PZSorter: moved " .. tostring(link.name) .. " to " .. tostring(record.name))
    return true
end

function Commands.unassign(player, args)
    print("PZSorter: unassign entered")
    local spot = spotOf(args)
    if not spot then
        return reject("bad arguments")
    end
    local byContainer = near(player, spot.x, spot.y, spot.z)
    local bySorter = near(player, tonumber(args.sorterX), tonumber(args.sorterY), tonumber(args.sorterZ))
    if not byContainer and not bySorter then
        return reject("player is not next to the container or the sorter")
    end
    local containerSquare = squareAt(spot.x, spot.y, spot.z)
    local sorterObject, record = findSorter(args.sorterId, tonumber(args.sorterX), tonumber(args.sorterY), tonumber(args.sorterZ))
    local squares = {}
    if containerSquare then
        squares[#squares + 1] = containerSquare
    end
    if sorterObject and sorterObject.getSquare then
        squares[#squares + 1] = sorterObject:getSquare()
    end
    if not allowedSquares(player, squares) then
        return false
    end
    if record then
        local removed, reason = Links.remove(record, spot)
        if removed then
            print("PZSorter: unassigned " .. tostring(removed.name) .. " from " .. tostring(record.name))
        else
            print("PZSorter: unassign found no link on the sorter (" .. tostring(reason) .. ")")
        end
        transmit(sorterObject)
    else
        print("PZSorter: unassign found no sorter, clearing the container only")
    end
    if containerSquare then
        local row = World.find(containerSquare, spot.index)
        if row then
            World.writeSorterId(row, nil)
        else
            print("PZSorter: unassign container is already gone")
        end
    end
    return true
end

local HANDLERS = {
    Assign = Commands.assign,
    Move = Commands.move,
    Unassign = Commands.unassign,
}

-- The menu calls this. Single player runs the handler in this state.
-- A multiplayer client only has the send, and the server runs the handler
-- from OnClientCommand below.
function Commands.request(player, command, args)
    print("PZSorter: " .. tostring(command) .. " requested")
    local handler = HANDLERS[command]
    if Config.onAuthority() and handler then
        print("PZSorter: running " .. tostring(command) .. " directly")
        handler(player, args)
        return
    end
    if sendClientCommand then
        print("PZSorter: command sent " .. tostring(command))
        sendClientCommand(player, Config.COMMAND_MODULE, command, args)
        return
    end
    print("PZSorter: no way to run " .. tostring(command))
end

local function onClientCommand(module, command, player, args)
    if module ~= Config.COMMAND_MODULE then
        return
    end
    local handler = HANDLERS[command]
    if not handler then
        return
    end
    print("PZSorter: OnClientCommand " .. tostring(command) .. " authority=" .. tostring(Config.onAuthority()))
    if not Config.onAuthority() then
        print("PZSorter: OnClientCommand skipped, this side does not save")
        return
    end
    handler(player, args)
end

Events.OnClientCommand.Add(onClientCommand)

print("PZSorter: container commands loaded (0.2.0)")

return Commands
