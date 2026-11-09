-- Which containers belong to which Sorter Crate.
--
-- Pure Lua, same as the range and naming rules, so the tests can run it
-- without the game. The right-click menu and the server command both call
-- these functions. That is what keeps "one sorter per container" from
-- meaning one thing on the menu and another thing in the save.
--
-- A link is one assigned container:
--   x, y, z     tile of the container
--   index       which container on that tile (0 is the first). A fridge
--               with a freezer is two indexes on one tile.
--   name        "Fridge 1", "Crate 2", and so on
--   priority    1 to 9, default 5. Higher wins a tie while sorting.
--   filter      categories, item types, and exclusions. {} accepts nothing.
--
-- The game's save turns a Lua array into string keys ("1", "2"). ipairs
-- then sees an empty list and the panel would forget every link after a
-- reload. each() reads both shapes. remove() writes a fresh array so the
-- rest of this file can keep using a normal list until the next save.

PZSorter = PZSorter or {}
PZSorter.Links = PZSorter.Links or {}

local Links = PZSorter.Links

require "PZSorter/Range"

local Range = PZSorter.Range

Links.DEFAULT_PRIORITY = 5

-- The arrows in the panel stop at 1 and 9. A missing or broken value is the
-- default, so an old save that has no priority still sorts as 5.
function Links.clampPriority(value)
    local number = tonumber(value)
    if number == nil then
        return Links.DEFAULT_PRIORITY
    end
    number = math.floor(number)
    if number < 1 then
        return 1
    end
    if number > 9 then
        return 9
    end
    return number
end

local function patternEscape(text)
    return (text:gsub("(%W)", "%%%1"))
end

-- Every link on a sorter, in index order, whether the save used 1, 2, 3
-- or "1", "2", "3".
function Links.each(links)
    local out = {}
    if type(links) ~= "table" then
        return out
    end
    local seen = {}
    for _, link in ipairs(links) do
        if type(link) == "table" and not seen[link] then
            seen[link] = true
            out[#out + 1] = link
        end
    end
    local extra = {}
    for key, link in pairs(links) do
        if type(link) == "table" and not seen[link] then
            seen[link] = true
            extra[#extra + 1] = { key = tonumber(key) or 0, link = link }
        end
    end
    table.sort(extra, function(a, b)
        return a.key < b.key
    end)
    for i = 1, #extra do
        out[#out + 1] = extra[i].link
    end
    return out
end

function Links.normalize(sorter)
    if type(sorter) ~= "table" then
        return
    end
    sorter.links = Links.each(sorter.links)
end

function Links.sameSpot(link, x, y, z, index)
    return type(link) == "table"
        and link.x == x
        and link.y == y
        and link.z == z
        and link.index == index
end

function Links.find(links, x, y, z, index)
    local list = Links.each(links)
    for i = 1, #list do
        if Links.sameSpot(list[i], x, y, z, index) then
            return list[i], i
        end
    end
    return nil, nil
end

-- Why a thing the player clicked cannot be assigned. nil means it can.
-- The menu builds `info` from the live object. The tests pass the same
-- table without the game.
--   sorter        one of our crates. A sorter does not sort into itself.
--   player        the player's own inventory
--   equippedBag   a bag that is worn or in hand
--   vehicle       trunk, seat, glovebox
--   corpse        a body on the ground
--   container     false when the tile has nothing to put items in
function Links.exclusion(info)
    if type(info) ~= "table" then
        return "not_container"
    end
    if info.sorter then
        return "sorter"
    end
    if info.player then
        return "player"
    end
    if info.equippedBag then
        return "equipped"
    end
    if info.vehicle then
        return "vehicle"
    end
    if info.corpse then
        return "corpse"
    end
    if not info.container then
        return "not_container"
    end
    return nil
end

-- "fridge" -> "Fridge". A blank type still gets a readable row name.
function Links.typeLabel(containerType)
    if type(containerType) ~= "string" then
        return "Container"
    end
    local bare = containerType:match("([^:%s]+)$")
    if not bare or bare == "" then
        return "Container"
    end
    return bare:sub(1, 1):upper() .. bare:sub(2)
end

-- Smallest "Fridge N" that this sorter is not already using. Unassigning
-- Fridge 1 lets the next fridge be Fridge 1 again. A renamed row that does
-- not match the pattern does not use up a number.
function Links.autoName(containerType, links)
    local label = Links.typeLabel(containerType)
    local used = {}
    local pattern = "^" .. patternEscape(label) .. " (%d+)$"
    for _, link in ipairs(Links.each(links)) do
        if type(link.name) == "string" then
            local digits = link.name:match(pattern)
            local number = tonumber(digits)
            if number and number >= 1 then
                used[number] = true
            end
        end
    end
    local number = 1
    while used[number] do
        number = number + 1
    end
    return label .. " " .. tostring(number)
end

local function spotNumbers(spot)
    if type(spot) ~= "table" then
        return nil
    end
    if type(spot.x) ~= "number" or type(spot.y) ~= "number" or type(spot.z) ~= "number" or type(spot.index) ~= "number" then
        return nil
    end
    return spot.x, spot.y, spot.z, spot.index
end

-- Add a container to this sorter. Fails when another sorter already owns
-- it: that case is a move, not a second link. currentSorterId is the id
-- stored on the container, or nil when nothing owns it.
function Links.add(sorter, spot, containerType, currentSorterId)
    if type(sorter) ~= "table" or sorter.id == nil then
        return nil, "no_sorter"
    end
    local x, y, z, index = spotNumbers(spot)
    if not x then
        return nil, "bad_spot"
    end
    if currentSorterId ~= nil and tostring(currentSorterId) ~= tostring(sorter.id) then
        return nil, "owned"
    end
    Links.normalize(sorter)
    if Links.find(sorter.links, x, y, z, index) then
        return nil, "duplicate"
    end
    local link = {
        x = x,
        y = y,
        z = z,
        index = index,
        name = Links.autoName(containerType, sorter.links),
        priority = Links.DEFAULT_PRIORITY,
        filter = {},
    }
    sorter.links[#sorter.links + 1] = link
    return link
end

function Links.remove(sorter, spot)
    if type(sorter) ~= "table" then
        return nil, "no_sorter"
    end
    local x, y, z, index = spotNumbers(spot)
    if not x then
        return nil, "bad_spot"
    end
    Links.normalize(sorter)
    local kept = {}
    local removed = nil
    for i = 1, #sorter.links do
        local link = sorter.links[i]
        if not removed and Links.sameSpot(link, x, y, z, index) then
            removed = link
        else
            kept[#kept + 1] = link
        end
    end
    sorter.links = kept
    if not removed then
        return nil, "not_linked"
    end
    return removed
end

-- Take the container off `fromSorter` and put it on `toSorter`. The row
-- name is chosen again on the destination, so two sorters can each have
-- their own "Crate 1".
function Links.move(fromSorter, toSorter, spot, containerType)
    if type(fromSorter) ~= "table" or type(toSorter) ~= "table" then
        return nil, "no_sorter"
    end
    if fromSorter.id == nil or toSorter.id == nil then
        return nil, "no_sorter"
    end
    if tostring(fromSorter.id) == tostring(toSorter.id) then
        return nil, "same_sorter"
    end
    local x, y, z, index = spotNumbers(spot)
    if not x then
        return nil, "bad_spot"
    end
    if not Links.find(fromSorter.links, x, y, z, index) then
        return nil, "not_linked"
    end
    if Links.find(toSorter.links, x, y, z, index) then
        return nil, "duplicate"
    end
    local removed = Links.remove(fromSorter, spot)
    if not removed then
        return nil, "not_linked"
    end
    return Links.add(toSorter, spot, containerType, nil)
end

-- Which living sorter has this container. Used to prove two sorters do
-- not both keep the same link.
function Links.lookup(sorters, spot)
    local x, y, z, index = spotNumbers(spot)
    if not x or type(sorters) ~= "table" then
        return nil, nil
    end
    for _, sorter in pairs(sorters) do
        if type(sorter) == "table" and not sorter.gone and sorter.id ~= nil then
            local link = Links.find(sorter.links, x, y, z, index)
            if link then
                return sorter, link
            end
        end
    end
    return nil, nil
end

-- What the Assign submenu shows for one container.
-- In-range sorters can be chosen. A sorter inside the 30-tile "nearby"
-- window but outside the sandbox range is still listed, with enabled
-- false, so the menu can grey it out. A sorter two floors away is not
-- nearby. The sorter that already owns the container is an Unassign row,
-- not a second Assign row.
function Links.menuEntries(sorters, target, rangeTiles, ownerId)
    local entries = {}
    if type(target) ~= "table" then
        return entries
    end
    local owner = nil
    local nearby = {}
    if type(sorters) == "table" then
        for _, sorter in pairs(sorters) do
            if type(sorter) == "table" and not sorter.gone and sorter.id ~= nil then
                if ownerId ~= nil and tostring(sorter.id) == tostring(ownerId) then
                    owner = sorter
                end
                -- A crate in somebody's inventory still owns its containers,
                -- so Unassign can name it, but it is not standing on a tile
                -- you can assign to.
                if not sorter.carried and sorter.x and sorter.y and sorter.z then
                    local horizontal = Range.chebyshev(sorter.x, sorter.y, target.x, target.y)
                    local floors = math.abs(sorter.z - target.z)
                    if horizontal <= Range.MAX and floors <= Range.FLOOR_SPAN then
                        nearby[#nearby + 1] = sorter
                    end
                end
            end
        end
    end
    table.sort(nearby, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    if ownerId ~= nil then
        entries[#entries + 1] = {
            id = tostring(ownerId),
            name = owner and owner.name or "Sorter",
            action = "unassign",
            enabled = true,
            x = owner and owner.x or nil,
            y = owner and owner.y or nil,
            z = owner and owner.z or nil,
        }
    end
    for i = 1, #nearby do
        local sorter = nearby[i]
        if ownerId == nil or tostring(sorter.id) ~= tostring(ownerId) then
            local action = ownerId ~= nil and "move" or "assign"
            entries[#entries + 1] = {
                id = tostring(sorter.id),
                name = sorter.name or "Sorter",
                action = action,
                enabled = Range.isInRange(
                    { x = sorter.x, y = sorter.y, z = sorter.z },
                    target,
                    rangeTiles
                ),
                x = sorter.x,
                y = sorter.y,
                z = sorter.z,
            }
        end
    end
    return entries
end

-- Panel dot. `loaded` false means the square is not in memory, which is
-- not the same as a container that was picked up. `found` false on a
-- loaded square is Missing.
function Links.status(sorterPos, link, rangeTiles, found, loaded)
    if loaded == false then
        return "unloaded"
    end
    if not found then
        return "missing"
    end
    if type(link) ~= "table" then
        return "missing"
    end
    if not Range.isInRange(sorterPos, { x = link.x, y = link.y, z = link.z }, rangeTiles) then
        return "range"
    end
    return "ok"
end

return Links
