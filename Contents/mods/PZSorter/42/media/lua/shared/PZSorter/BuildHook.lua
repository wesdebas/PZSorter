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
    local object = nil
    local character = nil
    if type(params) == "table" then
        object = params.thumpable or params.object
        character = params.character
    elseif params and type(params) == "userdata" then
        object = params
    end
    if not object then
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

return PZSorter.OnSpriteCreate