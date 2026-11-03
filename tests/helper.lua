-- Point busted at the shared Lua the game loads. Client and server files
-- call into the game, so the tests do not load them.
package.path = "Contents/mods/PZSorter/42/media/lua/shared/?.lua;" .. package.path
