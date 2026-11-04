-- Called by the entity script when a Sorter Crate is built.
--
-- SpriteConfig.OnCreate is the hook Build 42 uses for a finished entity,
-- including a build started with Build cheat. The game looks the function
-- up by this dotted name at the moment the crate is placed.
-- Events.OnObjectAdded does not run on the client for that placement, which
-- is why the name box never opened.
--
-- params.thumpable is the new object. params.character is the builder.
-- Vanilla's BuildRecipeCode.campfire.OnCreate reads the same table.

PZSorter = PZSorter or {}

function PZSorter.OnSpriteCreate(params)
    print("PZSorter: OnSpriteCreate entered")
    local object = nil
    local character = nil
    if type(params) == "table" then
        object = params.thumpable or params.object
        character = params.character
    elseif params and type(params) == "userdata" then
        object = params
    end
    if not object then
        print("PZSorter: OnSpriteCreate found no crate")
        return
    end
    local ok, err = pcall(function()
        if PZSorter.SorterData and PZSorter.SorterData.onBuilt then
            PZSorter.SorterData.onBuilt(object, character)
        end
        if PZSorter.NamePrompt and PZSorter.NamePrompt.onBuilt then
            PZSorter.NamePrompt.onBuilt(object, character)
        end
    end)
    if not ok then
        print("PZSorter: placement hook failed: " .. tostring(err))
    end
end

local function installBuildWrap()
    if not ISBuildIsoEntity or not ISBuildIsoEntity.setInfo then
        print("PZSorter: ISBuildIsoEntity not loaded yet")
        return
    end
    if ISBuildIsoEntity._PZSorterWrapped then
        return
    end
    ISBuildIsoEntity._PZSorterWrapped = true
    local oldSetInfo = ISBuildIsoEntity.setInfo
    function ISBuildIsoEntity:setInfo(square, north, sprite, openSprite)
        print("PZSorter: setInfo sprite=" .. tostring(sprite))
        local result = oldSetInfo(self, square, north, sprite, openSprite)
        if not PZSorter.Config.isSorterSpriteName(sprite) then
            return result
        end
        print("PZSorter: setInfo placed a Sorter Crate")
        local object = nil
        if square and square.getObjects then
            local objects = square:getObjects()
            for i = objects:size() - 1, 0, -1 do
                local candidate = objects:get(i)
                local name = candidate.getSprite and candidate:getSprite() and candidate:getSprite().getName and candidate:getSprite():getName()
                if name == sprite then
                    object = candidate
                    break
                end
            end
        end
        local character = self.character
        if not character and getSpecificPlayer then
            character = getSpecificPlayer(self.player or 0)
        end
        print("PZSorter: setInfo object=" .. tostring(object ~= nil))
        PZSorter.OnSpriteCreate({ thumpable = object, character = character })
        return result
    end
    print("PZSorter: wrapped ISBuildIsoEntity:setInfo")
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(installBuildWrap)
end
installBuildWrap()

print("PZSorter: placement hook defined")

return PZSorter.OnSpriteCreate