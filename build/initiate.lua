-- Creates the base `Core` table with an auto-vivifying __index, mirroring
-- qblib's build/initiate.lua. A module writes `function Core.player.get(...)`
-- with no boilerplate: the first reference to `Core.player` materialises the
-- module table. build/finalise.lua later walks Core and exports every function.
--
-- Unlike qblib's `QB` (which is exported as `<module>_<fn>`), Core is exported
-- FLAT (`<fn>`), because the requirement is exports.qbcore:getPlayer(id), not
-- exports.qbcore:player_getPlayer(id). finalise.lua asserts there are no
-- cross-module name collisions.

Core = setmetatable({}, {
    __index = function(self, key)
        local module = {}
        rawset(self, key, module)
        return module
    end
})
