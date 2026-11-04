-- What a picked-up Sorter Crate keeps in the item, and what placing it
-- back writes onto the new crate.
--
-- Pure Lua. The game hook calls these so a reload of the tests is the
-- round trip: crate record, then item data, then crate record again.
-- The id does not change. Links, their priority, and their filter tables
-- are copied, not shared, so editing one side later cannot leak into the
-- other. nameConfirmed is forced on, because this crate was already named.
-- A fresh build is the only thing that should open the name box.

PZSorter = PZSorter or {}
PZSorter.Carry = PZSorter.Carry or {}

local Carry = PZSorter.Carry

require "PZSorter/Links"

local Links = PZSorter.Links

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, inner in pairs(value) do
        out[key] = copyValue(inner)
    end
    return out
end

local function copyLink(link)
    return {
        x = link.x,
        y = link.y,
        z = link.z,
        index = link.index,
        name = link.name,
        priority = link.priority or Links.DEFAULT_PRIORITY,
        filter = copyValue(link.filter or {}),
    }
end

-- True when the crate's container has nothing in it. Vanilla furniture
-- will not pick up a container that still holds items. A missing count
-- is treated as "don't pick it up" so a failed lookup cannot delete loot.
function Carry.canPickUp(itemCount)
    if type(itemCount) ~= "number" then
        return false
    end
    return itemCount <= 0
end

function Carry.pack(record)
    local links = {}
    for _, link in ipairs(Links.each(record and record.links)) do
        links[#links + 1] = copyLink(link)
    end
    return {
        schema = record and record.schema or 1,
        id = record and record.id,
        name = record and record.name,
        nameConfirmed = true,
        links = links,
    }
end

-- The record for the crate that was just placed. x, y, z are the new tile.
-- The old spot is not kept: range is measured from where it stands now.
function Carry.restore(packed, x, y, z)
    local links = {}
    for _, link in ipairs(Links.each(packed and packed.links)) do
        links[#links + 1] = copyLink(link)
    end
    return {
        schema = packed and packed.schema or 1,
        id = packed and packed.id,
        name = packed and packed.name,
        nameConfirmed = true,
        appliedName = packed and packed.name,
        links = links,
        x = x,
        y = y,
        z = z,
    }
end

-- Drop one link while the crate is in the inventory. The container's own
-- sorter id is cleared by the command. This is the copy on the item.
function Carry.dropLink(packed, spot)
    if type(packed) ~= "table" then
        return nil, "no_sorter"
    end
    local holder = { id = packed.id, links = packed.links }
    local removed, reason = Links.remove(holder, spot)
    if removed then
        packed.links = holder.links
    end
    return removed, reason
end

-- World-list row while the item is in a bag. carried stops the assign
-- menu from offering a crate that is not standing in the world. The old
-- tile is kept only so a failed place can still be found in the log.
function Carry.asCarried(existing, packed)
    local entry = {
        id = packed and packed.id,
        name = packed and packed.name,
        nameConfirmed = true,
        carried = true,
        gone = false,
        links = {},
    }
    if type(existing) == "table" then
        entry.x = existing.x
        entry.y = existing.y
        entry.z = existing.z
    end
    for _, link in ipairs(Links.each(packed and packed.links)) do
        entry.links[#entry.links + 1] = copyLink(link)
    end
    return entry
end

return Carry
