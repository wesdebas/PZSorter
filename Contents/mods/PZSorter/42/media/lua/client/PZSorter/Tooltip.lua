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
require "PZSorter/Names"

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

function Tooltip.titleFor(object)
    local record = recordOf(object)
    local container = object and object.getContainer and object:getContainer()
    local custom = container and container.getCustomName and container:getCustomName()
    local title, adopt = PZSorter.Names.reconcile(record and record.name, custom, record and record.appliedName)
    if adopt then
        print("PZSorter: keeping vanilla name " .. tostring(title))
        if record then
            record.name = title
            record.nameConfirmed = true
            -- The container already shows this vanilla name. Remember that
            -- we accepted it, so the next refresh does not treat it as new.
            record.appliedName = title
        end
        if Config.onAuthority() and PZSorter.SorterData and PZSorter.SorterData.setName and object.getSquare then
            local square = object:getSquare()
            if square then
                PZSorter.SorterData.setName(getSpecificPlayer(0), {
                    id = record and record.id or nil,
                    x = square:getX(),
                    y = square:getY(),
                    z = square:getZ(),
                    name = title,
                })
            end
        end
    end
    return title
end

function Tooltip.applyName(object)
    if not object then
        return
    end
    local container = object.getContainer and object:getContainer()
    local current = container and container.getCustomName and container:getCustomName()
    local title = Tooltip.titleFor(object)
    local record = recordOf(object)
    -- Don't write the name back when it is already what the loot window shows.
    -- That was wiping a vanilla rename on the next open.
    if current == title then
        if record and record.appliedName ~= title then
            record.appliedName = title
        end
        return
    end
    -- IsoObject:setName takes a string. The container title is a separate
    -- call: ItemContainer:setCustomName(string), which getCustomName reads.
    if type(title) == "string" and object.setName and type(object.setName) == "function" then
        object:setName(title)
    end
    if type(title) == "string" and container and type(container.setCustomName) == "function" then
        container:setCustomName(title)
    end
    -- This write is ours. A later refresh must not read it back as a
    -- vanilla rename and throw away the name the player just typed.
    if record then
        record.appliedName = title
    end
end

local function retitleOpenWindows(page)
    if not page or not page.backpacks then
        return
    end
    for i = 1, #page.backpacks do
        local button = page.backpacks[i]
        local container = button and button.inventory
        local parent = container and container.getParent and container:getParent()
        if parent and Config.isSorterSpriteName(spriteNameOf(parent)) then
            local current = container.getCustomName and container:getCustomName()
            local title = Tooltip.titleFor(parent)
            button.name = title
            button.tooltip = title
            if button.setTitle then
                button:setTitle(title)
            end
            if type(title) == "string" and current ~= title and container.setCustomName and type(container.setCustomName) == "function" then
                container:setCustomName(title)
            end
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
    local text = Tooltip.titleFor(object)
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

local function onRefreshContainers(page, state)
    if state ~= "end" then
        return
    end
    local ok, err = pcall(function()
        retitleOpenWindows(page)
    end)
    if not ok then
        print("PZSorter: loot title failed: " .. tostring(err))
    end
end

Events.OnTick.Add(onTick)
Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)

return Tooltip
