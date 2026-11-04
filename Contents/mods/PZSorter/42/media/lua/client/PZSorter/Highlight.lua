-- Glow on the containers a sorter is linked to.
--
-- 42.21's IsoObject highlight takes the player index, then on/off, then
-- whether the glow should last only one frame. We pass false for that last
-- flag so the container stays lit while the panel is open. The outline is
-- the second glow vanilla uses for "look at this". Both are tried. A build
-- that renamed one of them still gets the other, and a throw is printed
-- instead of breaking the panel.

PZSorter = PZSorter or {}
PZSorter.Highlight = PZSorter.Highlight or {}

local Highlight = PZSorter.Highlight

local lit = {}
local litPlayer = 0

local function apply(object, playerNum, on)
    if not object then
        return
    end
    local function try(fn)
        if fn then
            pcall(fn)
        end
    end
    if on then
        try(function()
            if object.setHighlightColor then
                object:setHighlightColor(playerNum, 0.25, 0.9, 0.35, 1)
            end
        end)
        try(function()
            if object.setOutlineHighlightCol then
                object:setOutlineHighlightCol(playerNum, 0.25, 0.9, 0.35, 1)
            end
        end)
    end
    try(function()
        if object.setHighlighted then
            object:setHighlighted(playerNum, on and true or false, false)
        end
    end)
    try(function()
        if object.setOutlineHighlight then
            object:setOutlineHighlight(playerNum, on and true or false)
        end
    end)
end

function Highlight.clear()
    for i = 1, #lit do
        apply(lit[i], litPlayer, false)
    end
    lit = {}
end

-- Replace whatever was glowing with this list. Passing one object is how a
-- hovered row lights only that container. Passing every linked object is
-- the normal panel glow. An empty list clears the glow.
function Highlight.show(objects, playerNum)
    Highlight.clear()
    litPlayer = playerNum or 0
    if type(objects) ~= "table" then
        return
    end
    for i = 1, #objects do
        local object = objects[i]
        if object then
            apply(object, litPlayer, true)
            lit[#lit + 1] = object
        end
    end
end

return Highlight
