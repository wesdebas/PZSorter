-- Hover text for a Sorter Crate.
--
-- The tile's own name is always "Sorter Crate". The name the player typed
-- lives in the crate's mod data, which is a per-crate value, so it cannot
-- be baked into the sprite. Two things read it:
--   * The container title, when the loot window is open.
--   * A small tooltip while the mouse is over the crate in the world.
-- Both are reapplied when a square loads, because a reload builds a fresh
-- object and the Java container name starts out blank.

require "ISUI/ISToolTip"
require "PZSorter/Config"

PZSorter = PZSorter or {}
PZSorter.Tooltip = PZSorter.Tooltip or {}

local Tooltip = PZSorter.Tooltip
local Config = PZSorter.Config

if Tooltip._hooked then
    return Tooltip
end
Tooltip._hooked = true

local hover = nil
local hoverFailed = false

local function recordOf(object)
    if not object or not object.getModData then
        return nil
    end
    local modData = object:getModData()
    if not modData then
        return nil
    end
    return modData[Config.MOD_DATA_KEY]
end

local function spriteNameOf(object)
    if not object or not object.getSprite then
        return nil
    end
    local sprite = object:getSprite()
    if not sprite or not sprite.getName then
        return nil
    end
    return sprite:getName()
end

function Tooltip.applyName(object)
    local record = recordOf(object)
    if not record or type(record.name) ~= "string" or record.name == "" then
        return
    end
    -- setName is not on every build. The container title is the one the
    -- loot window uses, and it is the one we care about most after hover.
    if object.setName then
        pcall(function()
            object:setName(record.name)
        end)
    end
    if object.getContainer then
        local container = object:getContainer()
        if container and container.setCustomName then
            pcall(function()
                container:setCustomName(record.name)
            end)
        end
    end
end

local function hideHover()
    if hover then
        hover:setVisible(false)
    end
end

local function showHover(text)
    if not hover then
        hover = ISToolTip:new()
        hover:initialise()
        hover:addToUIManager()
        hover:setVisible(false)
        hover.followMouse = false
    end
    hover:setName(text)
    if hover.setDescription then
        hover:setDescription("")
    end
    hover.description = ""
    local x = getMouseX() + 18
    local y = getMouseY() + 18
    hover:setX(x)
    hover:setY(y)
    hover:setVisible(true)
    if hover.bringToTop then
        hover:bringToTop()
    end
end

local function sorterUnderMouse()
    local player = getSpecificPlayer(0)
    if not player or (player.isDead and player:isDead()) then
        return nil
    end
    local cell = getCell()
    if not cell or not screenToIsoX or not screenToIsoY then
        return nil
    end
    local z = math.floor(player:getZ())
    local mx = getMouseX()
    local my = getMouseY()
    local worldX = screenToIsoX(0, mx, my, z)
    local worldY = screenToIsoY(0, mx, my, z)
    if not worldX or not worldY then
        return nil
    end
    local square = cell:getGridSquare(math.floor(worldX), math.floor(worldY), z)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Config.isSorterSpriteName(spriteNameOf(object)) then
            return object
        end
    end
    return nil
end

local function onTick()
    -- OnTick also runs on the main menu, where there is no player and no
    -- world. Bail before touching the mouse or the context menu.
    if not getSpecificPlayer or not getSpecificPlayer(0) then
        hideHover()
        return
    end
    -- The mouse-to-tile helper is a guess when a tall sprite overlaps the
    -- square. For a crate that sits on one tile it is the square you are
    -- pointing at, which is what the hover name needs.
    local menu = getPlayerContextMenu and getPlayerContextMenu(0)
    if menu and menu.isVisible and menu:isVisible() then
        hideHover()
        return
    end
    local ok, object = pcall(sorterUnderMouse)
    if not ok or not object then
        hideHover()
        return
    end
    Tooltip.applyName(object)
    local record = recordOf(object)
    local text = record and record.name or nil
    if type(text) ~= "string" or text == "" then
        text = getText("IGUI_PZSorter_DefaultObjectName")
    end
    local shown, err = pcall(function()
        showHover(text)
    end)
    if not shown then
        hideHover()
        if not hoverFailed then
            hoverFailed = true
            print("PZSorter: hover tooltip failed: " .. tostring(err))
        end
    end
end

local function onLoadGridsquare(square)
    if not square or not square.getObjects then
        return
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Config.isSorterSpriteName(spriteNameOf(object)) then
            Tooltip.applyName(object)
        end
    end
end

Events.OnTick.Add(onTick)
Events.LoadGridsquare.Add(onLoadGridsquare)

return Tooltip
