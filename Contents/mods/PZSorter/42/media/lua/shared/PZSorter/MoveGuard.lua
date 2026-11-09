-- The last check before an item leaves the Sorter Crate.
--
-- A move goes into one real container that still has room, or it does not
-- happen. The ground is a container of type "floor". Putting an item there
-- drops it outside the crate, so a floor destination is refused and the
-- item stays in the sorter. If the item was already taken out and the add
-- fails, it goes back into the source container, not onto the ground.

PZSorter = PZSorter or {}
PZSorter.MoveGuard = PZSorter.MoveGuard or {}

local Guard = PZSorter.MoveGuard

-- dest is a plain table, so the tests can run this without the game.
--   type     container:getType(), "floor" for the ground
--   floor    true when the caller already knows it is the ground
--   addable  the container has AddItem
--   sameAsSource  the destination is the sorter itself
--   room     true when the item fits by weight or capacity right now
function Guard.allow(dest)
    if type(dest) ~= "table" then
        return false, "invalid"
    end
    if dest.floor or dest.type == "floor" then
        return false, "floor"
    end
    if dest.sameAsSource or dest.addable == false then
        return false, "invalid"
    end
    if dest.room == false then
        return false, "full"
    end
    return true
end

-- added is whether dest:AddItem kept the item. A failed add must be put
-- back in the sorter. This never says to drop the item on the ground.
function Guard.afterRemove(added)
    if added then
        return "done"
    end
    return "restore"
end

return Guard
