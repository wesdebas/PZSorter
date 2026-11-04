-- Who may assign a container or open a sorter.
--
-- Outside a safehouse, anyone can, the same way anyone can use a vanilla
-- crate. Inside a safehouse, only members can. 42.21 exposes this as
-- SafeHouse.getSafeHouse(square) and safehouse:playerAllowed(player).
-- If that call is missing or throws, we allow the action and print a line
-- so the console shows it. Step 5 can tighten multiplayer if this was wrong.

PZSorter = PZSorter or {}
PZSorter.Access = PZSorter.Access or {}

local Access = PZSorter.Access

function Access.allowed(player, square)
    if not player or not square then
        return true
    end
    if not SafeHouse or not SafeHouse.getSafeHouse then
        if not Access._noted then
            Access._noted = true
            print("PZSorter: SafeHouse API missing, not enforcing membership")
        end
        return true
    end
    local ok, house = pcall(function()
        return SafeHouse.getSafeHouse(square)
    end)
    if not ok then
        print("PZSorter: safehouse lookup failed: " .. tostring(house))
        return true
    end
    if not house then
        return true
    end
    local allowedOk, allowed = pcall(function()
        return house:playerAllowed(player)
    end)
    if not allowedOk then
        print("PZSorter: safehouse membership check failed: " .. tostring(allowed))
        return true
    end
    if allowed then
        return true
    end
    print("PZSorter: safehouse blocked at " .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ()))
    return false
end

return Access
