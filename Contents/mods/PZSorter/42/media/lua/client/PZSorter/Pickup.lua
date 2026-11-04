-- Vanilla pickup and place for the Sorter Crate.
--
-- IsMoveAble plus CustomItem = PZSorter.SorterCrate is what makes the
-- move action create an item. Before that, the animation ran and then
-- created nothing, and the crate stayed where it was. This file copies
-- the saved name and links onto that item, and writes them back when the
-- item is placed. The name box stays closed because the restored record
-- is already confirmed.

require "PZSorter/Config"
require "PZSorter/Carry"
require "PZSorter/CarryFind"
require "PZSorter/Names"

PZSorter = PZSorter or {}
PZSorter.Pickup = PZSorter.Pickup or {}

local Pickup = PZSorter.Pickup
local Config = PZSorter.Config
local Carry = PZSorter.Carry
local Find = PZSorter.CarryFind

if Pickup._hooked then
    return Pickup
end

local function spriteNameOf(object)
    if not object or not object.getSprite then
        return nil
    end
    local ok, sprite = pcall(function()
        return object:getSprite()
    end)
    if not ok or not sprite or not sprite.getName then
        return nil
    end
    local named, name = pcall(function()
        return sprite:getName()
    end)
    if named then
        return name
    end
    return nil
end

local function isSorterObject(object)
    return Config.isSorterSpriteName(spriteNameOf(object))
end

local function sorterOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if isSorterObject(object) then
            return object
        end
    end
    return nil
end

local function objectStillThere(square, object)
    if not square or not square.getObjects or not object then
        return false
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == object then
            return true
        end
    end
    return false
end

local function itemCount(object)
    if not object or not object.getContainer then
        return 0
    end
    local ok, container = pcall(function()
        return object:getContainer()
    end)
    if not ok or not container then
        return 0
    end
    if container.getItems then
        local listed, items = pcall(function()
            return container:getItems()
        end)
        if listed and items and items.size then
            return items:size()
        end
    end
    if container.isEmpty then
        local emptyOk, empty = pcall(function()
            return container:isEmpty()
        end)
        if emptyOk and not empty then
            return 1
        end
    end
    return 0
end

local function halo(player)
    if player and player.setHaloNote and getText then
        pcall(function()
            player:setHaloNote(getText("IGUI_PZSorter_PickupFull"))
        end)
    end
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

local function looksLikePlayer(value)
    return value and value.getInventory and (value.getCurrentSquare or value.getPlayerNum)
end

local function looksLikeSquare(value)
    return value and value.getObjects and value.getX and not value.getInventory
end

local function describeArgs(...)
    local object, player, square, item = nil, nil, nil, nil
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "userdata" or type(value) == "table" then
            if not object and isSorterObject(value) then
                object = value
            elseif not item and value.getModData and value.getFullType then
                local ok, fullType = pcall(function()
                    return value:getFullType()
                end)
                if ok and fullType == "PZSorter.SorterCrate" then
                    item = value
                end
            elseif not player and looksLikePlayer(value) then
                player = value
            elseif not square and looksLikeSquare(value) then
                square = value
            end
        end
    end
    if not object and square then
        object = sorterOnSquare(square)
    end
    if not square and object and object.getSquare then
        local ok, found = pcall(function()
            return object:getSquare()
        end)
        if ok then
            square = found
        end
    end
    if not player and getSpecificPlayer then
        player = getSpecificPlayer(0)
    end
    return object, player, square, item
end

local function markCarried(player, packed)
    local item = Find.findFresh(player)
    if not item then
        print("PZSorter: pickup did not create an item")
        return false
    end
    Find.write(item, packed)
    if PZSorter.SorterData and PZSorter.SorterData.getWorld then
        local world = PZSorter.SorterData.getWorld()
        local id = tostring(packed.id)
        world.sorters = world.sorters or {}
        world.sorters[id] = Carry.asCarried(world.sorters[id], packed)
        if isServer and isServer() and ModData and ModData.transmit then
            pcall(function()
                ModData.transmit(Config.MOD_DATA_KEY)
            end)
        end
    end
    local count = packed.links and #packed.links or 0
    print("PZSorter: pickup stored name=" .. tostring(packed.name) .. " links=" .. tostring(count))
    return true
end

local function applyPlace(square, packed)
    local object = sorterOnSquare(square)
    if not object then
        print("PZSorter: place found no crate on the square")
        return false
    end
    -- Vanilla often copies the item mod data onto the new crate, which is
    -- why the name and rows showed up with no log line. That copy has no
    -- tile position and leaves the world row marked carried. Write the
    -- record again from the square the player actually used.
    local record = Carry.restore(packed, square:getX(), square:getY(), square:getZ())
    object:getModData()[Config.MOD_DATA_KEY] = record
    if PZSorter.SorterData and PZSorter.SorterData.getWorld then
        local world = PZSorter.SorterData.getWorld()
        world.sorters = world.sorters or {}
        PZSorter.Names.absorb(world.sorters, record)
    end
    if PZSorter.SorterData and PZSorter.SorterData.applyContainerName then
        PZSorter.SorterData.applyContainerName(object)
    end
    if object.transmitModData then
        object:transmitModData()
    end
    return true
end

-- Pickup calls pickUpMoveable from pickUpMoveableViaCursor. Place does not
-- do the same with placeMoveable: the action calls placeMoveableViaCursor
-- on its own, so wrapping only placeMoveable never ran and never logged.
-- Every place entry, plus the action's complete(), shares one depth so a
-- nested call logs the restore once.
local placeDepth = 0

local function packedFrom(item)
    if not item or not item.getModData then
        return nil
    end
    local ok, modData = pcall(function()
        return item:getModData()
    end)
    if not ok or type(modData) ~= "table" then
        return nil
    end
    local saved = modData[Config.MOD_DATA_KEY]
    if type(saved) ~= "table" or saved.id == nil then
        return nil
    end
    return saved
end

local function handItem(player)
    if not player then
        return nil
    end
    if player.getPrimaryHandItem then
        local ok, hand = pcall(function()
            return player:getPrimaryHandItem()
        end)
        if ok and packedFrom(hand) then
            return hand
        end
    end
    if player.getSecondaryHandItem then
        local ok, hand = pcall(function()
            return player:getSecondaryHandItem()
        end)
        if ok and packedFrom(hand) then
            return hand
        end
    end
    return nil
end

local function beginPlace(packed)
    placeDepth = placeDepth + 1
    local outer = placeDepth == 1
    -- The outer call is ISMoveablesAction:complete. It often does not have
    -- the item in its arguments; the cursor method it calls does. Arm the
    -- saved record on whichever of them sees it first.
    if packed and not Carry.pending then
        Carry.pending = Carry.pack(packed)
        print("PZSorter: place starting name=" .. tostring(packed.name))
    end
    return outer
end

local function endPlace(square, outer)
    if outer and Carry.pending then
        local restored = Carry.pending
        local count = restored.links and #restored.links or 0
        if square then
            applyPlace(square, restored)
            print("PZSorter: place restored name=" .. tostring(restored.name) .. " links=" .. tostring(count))
        else
            print("PZSorter: place had no square, saved record was not applied")
        end
        Carry.pending = nil
    end
    if placeDepth > 0 then
        placeDepth = placeDepth - 1
    end
    if outer and square then
        local object = sorterOnSquare(square)
        local sprite = object and spriteNameOf(object)
        if sprite then
            local facing = "?"
            for letter, name in pairs(Config.FACINGS) do
                if name == sprite then
                    facing = letter
                end
            end
            print("PZSorter: place facing=" .. facing .. " sprite=" .. sprite)
        end
    end
end

local function wrapPickup(methodName)
    local old = ISMoveableSpriteProps[methodName]
    if type(old) ~= "function" then
        return false
    end
    ISMoveableSpriteProps[methodName] = function(self, ...)
        local object, player, square = describeArgs(...)
        if object and not Carry.canPickUp(itemCount(object)) then
            print("PZSorter: pickup refused, crate is not empty (" .. tostring(itemCount(object)) .. ")")
            halo(player)
            return
        end
        local packed = nil
        if object then
            local record = recordOf(object)
            if record then
                packed = Carry.pack(record)
                print("PZSorter: pickup started name=" .. tostring(record.name) .. " links=" .. tostring(#packed.links))
            else
                print("PZSorter: pickup started with no saved record")
            end
        end
        local result = old(self, ...)
        if packed then
            if object and objectStillThere(square, object) then
                print("PZSorter: pickup left the crate in the world")
            else
                markCarried(player, packed)
            end
        end
        return result
    end
    return true
end

local function wrapPlace(methodName)
    local old = ISMoveableSpriteProps[methodName]
    if type(old) ~= "function" or ISMoveableSpriteProps["_PZSorter" .. methodName] then
        return false
    end
    ISMoveableSpriteProps["_PZSorter" .. methodName] = true
    ISMoveableSpriteProps[methodName] = function(self, ...)
        local _, player, square, item = describeArgs(...)
        if not packedFrom(item) then
            item = handItem(player)
        end
        local packed = packedFrom(item)
        local outer = beginPlace(packed)
        local result = old(self, ...)
        endPlace(square, outer)
        return result
    end
    return true
end

local function logLoadedSprites()
    if Pickup._propsLogged then
        return
    end
    if not getSprite then
        return
    end
    Pickup._propsLogged = true
    for index = 0, 3 do
        local spriteName = "pzsorter_crate_01_" .. tostring(index)
        local sprite = getSprite(spriteName)
        if not sprite or not sprite.getProperties then
            print("PZSorter: sprite props " .. spriteName .. " missing")
        else
            local props = sprite:getProperties()
            local function flag(key)
                if props and props.has and props:has(key) then
                    local value = props.get and props:get(key) or ""
                    if value == nil or value == "" then
                        return "yes"
                    end
                    return tostring(value)
                end
                return "-"
            end
            print("PZSorter: sprite props " .. spriteName
                .. " Facing=" .. flag("Facing")
                .. " GroupName=" .. flag("GroupName")
                .. " CustomName=" .. flag("CustomName")
                .. " IsMoveAble=" .. flag("IsMoveAble")
                .. " Noffset=" .. flag("Noffset")
                .. " Woffset=" .. flag("Woffset")
                .. " Soffset=" .. flag("Soffset")
                .. " Eoffset=" .. flag("Eoffset"))
        end
    end
end

local function install()
    if Pickup._hooked then
        return
    end
    if not ISMoveableSpriteProps then
        print("PZSorter: ISMoveableSpriteProps not loaded yet")
        return
    end
    Pickup._hooked = true
    local pickupName = nil
    if type(ISMoveableSpriteProps.pickUpMoveable) == "function" then
        pickupName = "pickUpMoveable"
    elseif type(ISMoveableSpriteProps.pickUpMoveableViaCursor) == "function" then
        pickupName = "pickUpMoveableViaCursor"
    end
    local pickupWrapped = pickupName and wrapPickup(pickupName)
    local placeNames = {}
    local placeWrapped = false
    for _, methodName in ipairs({ "placeMoveableViaCursor", "placeMoveable", "placeMoveableInternal" }) do
        if wrapPlace(methodName) then
            placeNames[#placeNames + 1] = methodName
            placeWrapped = true
        end
    end
    print("PZSorter: pickup hook installed pickup=" .. tostring(pickupName) .. " place=" .. table.concat(placeNames, ",") .. " wrapped=" .. tostring(pickupWrapped and placeWrapped))

    -- R during place increments the inventory index, not the face, unless
    -- hasFaces() is true and something sets cursorFacing. Joypad X calls
    -- rotateWhilePlacing. Keyboard R does not. For this crate, R should
    -- walk getIndexedFaces(), which is N, W, S, E from the offsets.
    if ISMoveableCursor and type(ISMoveableCursor.rotateKey) == "function" and not ISMoveableCursor._PZSorterRotate then
        ISMoveableCursor._PZSorterRotate = true
        local oldRotateKey = ISMoveableCursor.rotateKey
        function ISMoveableCursor:rotateKey(key, joypad)
            local rotate = joypad and true or false
            if not rotate and getCore and KeybindId and getCore().isKey then
                rotate = getCore():isKey(KeybindId.ROTATE_BUILDING, key) and true or false
            end
            local mode = ISMoveableCursor.mode and ISMoveableCursor.mode[self.player]
            if rotate and mode == "place" then
                local objects = self.objectListCache
                if (not objects or not objects[self.objectIndex]) and self.getInventoryObjectList then
                    objects = self:getInventoryObjectList()
                end
                local entry = objects and objects[self.objectIndex]
                local props = entry and entry.moveProps
                local spriteName = props and props.spriteName
                if props and Config.isSorterSpriteName(spriteName) then
                    local names = {}
                    if props.getIndexedFaces and props.hasFaces and props:hasFaces() then
                        local indexed = props:getIndexedFaces()
                        if indexed then
                            for i = 1, #indexed do
                                names[#names + 1] = tostring(indexed[i])
                            end
                        end
                    end
                    if not Pickup._rotateLogged then
                        Pickup._rotateLogged = true
                        print("PZSorter: rotate faces found=" .. tostring(#names) .. " [" .. table.concat(names, ", ") .. "]")
                    end
                    if #names > 1 and self.rotateWhilePlacing then
                        self:rotateWhilePlacing()
                        return
                    end
                end
            end
            return oldRotateKey(self, key, joypad)
        end
    end

    if ISMoveablesAction and type(ISMoveablesAction.complete) == "function" and not ISMoveablesAction._PZSorterPlace then
        ISMoveablesAction._PZSorterPlace = true
        local oldComplete = ISMoveablesAction.complete
        function ISMoveablesAction:complete()
            local mode = tostring(self.mode or "")
            local placing = mode == "place" or mode == "placeface"
            local square = self.square
            local packed = nil
            if placing then
                packed = packedFrom(self.item) or packedFrom(handItem(self.character))
                if not packed then
                    print("PZSorter: place complete mode=" .. mode .. " with no sorter item")
                end
            elseif mode ~= "pickup" and mode ~= "scrap" and mode ~= "repair" and mode ~= "rotate" then
                packed = packedFrom(self.item) or packedFrom(handItem(self.character))
                if packed then
                    print("PZSorter: move action mode=" .. mode)
                    placing = true
                end
            end
            local outer = false
            if placing then
                outer = beginPlace(packed)
            end
            local result = oldComplete(self)
            if placing then
                endPlace(square, outer)
            end
            return result
        end
    end

    if ISMoveablesAction and type(ISMoveablesAction.isValid) == "function" and not ISMoveablesAction._PZSorterPickup then
        ISMoveablesAction._PZSorterPickup = true
        local oldValid = ISMoveablesAction.isValid
        function ISMoveablesAction:isValid()
            local mode = self.mode
            if mode == "pickup" then
                local object = self.object or self.srcObj
                if not object and self.square then
                    object = sorterOnSquare(self.square)
                end
                local sprite = self.moveProps and (self.moveProps.spriteName or self.moveProps.sprite or self.moveProps.name)
                local ours = (object and isSorterObject(object)) or Config.isSorterSpriteName(sprite)
                if ours and object and not Carry.canPickUp(itemCount(object)) then
                    if not self._pzSorterTold then
                        self._pzSorterTold = true
                        print("PZSorter: pickup refused, crate is not empty (" .. tostring(itemCount(object)) .. ")")
                        halo(self.character)
                    end
                    return false
                end
            end
            return oldValid(self)
        end
    end
end

    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(function()
            install()
            logLoadedSprites()
        end)
    end
    install()
    logLoadedSprites()

print("PZSorter: pickup loaded (0.2.0)")

return Pickup
