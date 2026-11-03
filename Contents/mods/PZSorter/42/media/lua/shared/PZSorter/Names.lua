-- Naming rules for a Sorter Crate.
--
-- This file is pure Lua. It does not call into the game, so the tests can
-- run it with busted. The name box and the server both call these functions,
-- which keeps "what is a legal name" from drifting between the two.

PZSorter = PZSorter or {}
PZSorter.Names = PZSorter.Names or {}

local Names = PZSorter.Names

-- The prompt refuses anything outside this length, after trimming.
Names.MIN_LENGTH = 1
Names.MAX_LENGTH = 24

-- Drop spaces (and other whitespace) at the ends. Spaces in the middle stay,
-- so "Main Base" is a real name and "  Main Base  " is the same name.
function Names.trim(text)
    if type(text) ~= "string" then
        return ""
    end
    -- gsub returns the new string and a count. The parentheses keep only the
    -- string, so callers can use the result directly.
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Count characters, not bytes. Lua 5.1 has no utf8 library, and a name like
-- "Café" is more than four bytes. We walk the UTF-8 sequence so the 24
-- character limit means 24 characters. A broken byte counts as one, so a
-- bad string still ends instead of looping.
local function characterCount(text)
    local count = 0
    local i = 1
    local length = #text
    while i <= length do
        local byte = string.byte(text, i)
        local size = 1
        if byte >= 0xF0 and byte <= 0xF7 then
            size = 4
        elseif byte >= 0xE0 then
            size = 3
        elseif byte >= 0xC0 then
            size = 2
        end
        if i + size - 1 > length then
            size = 1
        end
        i = i + size
        count = count + 1
    end
    return count
end

-- Returns the trimmed name, or nil plus a reason the prompt can show.
-- Reasons are "empty" and "too_long". The server uses the same reasons.
function Names.validate(raw)
    local name = Names.trim(raw)
    if name == "" then
        return nil, "empty"
    end
    if characterCount(name) > Names.MAX_LENGTH then
        return nil, "too_long"
    end
    if characterCount(name) < Names.MIN_LENGTH then
        return nil, "empty"
    end
    return name
end

-- "Sorter 12" -> 12. A custom name does not block a number. "Sorter 01"
-- does, because the digits are still 1. "sorter 1" does not: the word has
-- to match the capital S the prompt itself writes.
local function generatedNumber(name)
    if type(name) ~= "string" then
        return nil
    end
    local digits = name:match("^Sorter (%d+)$")
    if not digits then
        return nil
    end
    return tonumber(digits)
end

-- Smallest "Sorter N" that is not already in the list, starting at 1.
-- Dismantling a crate frees its number. Renaming "Sorter 1" to "Pantry"
-- frees 1 as well, because the generated name is no longer in use.
function Names.nextDefault(existingNames)
    local used = {}
    if type(existingNames) == "table" then
        for _, name in pairs(existingNames) do
            local number = generatedNumber(name)
            if number and number >= 1 then
                used[number] = true
            end
        end
    end
    local number = 1
    while used[number] do
        number = number + 1
    end
    return "Sorter " .. tostring(number)
end

-- The world save stores each crate as a record with a name field. This is
-- the list the server passes in when a new crate needs a suggested name.
function Names.nextFromRecords(records)
    local names = {}
    if type(records) == "table" then
        for _, record in pairs(records) do
            if type(record) == "table" and type(record.name) == "string" then
                names[#names + 1] = record.name
            end
        end
    end
    return Names.nextDefault(names)
end

return Names
