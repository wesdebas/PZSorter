local Config = require("PZSorter.Config")

describe("single player side flags", function()
    local oldClient
    local oldServer

    before_each(function()
        oldClient = _G.isClient
        oldServer = _G.isServer
    end)

    after_each(function()
        _G.isClient = oldClient
        _G.isServer = oldServer
    end)

    it("treats both flags false as the local game", function()
        _G.isClient = function() return false end
        _G.isServer = function() return false end
        assert.is_true(Config.onAuthority())
        assert.is_true(Config.onPlayer())
    end)

    it("keeps a multiplayer client off the save and a dedicated server off the ui", function()
        _G.isClient = function() return true end
        _G.isServer = function() return false end
        assert.is_false(Config.onAuthority())
        assert.is_true(Config.onPlayer())

        _G.isClient = function() return false end
        _G.isServer = function() return true end
        assert.is_true(Config.onAuthority())
        assert.is_false(Config.onPlayer())
    end)
end)
