-- How far a sorter can reach.
--
-- Assigning a container (step 2) calls isInRange. The menu and the server
-- both use it, so "20 tiles" cannot mean two different things.
--
-- The owner decided the shape: a square, counted in tiles, on the crate's
-- floor and one floor above and one floor below. A square in tile steps is
-- Chebyshev distance: the larger of the east-west gap and the north-south
-- gap. Diagonal counts the same as straight. A circle (ordinary straight-line
-- distance) would call the corner of that square "too far", and that is not
-- what was asked for.

PZSorter = PZSorter or {}
PZSorter.Range = PZSorter.Range or {}

local Range = PZSorter.Range

Range.MIN = 20
Range.MAX = 30
Range.DEFAULT = 20
-- Floors the sorter can reach, not counting its own floor.
Range.FLOOR_SPAN = 1

local function asInteger(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    return math.floor(number)
end

-- The sandbox option is an integer from 20 to 30. Anything missing or
-- outside that (an old save, a hand-edited file) falls back inside the
-- same limits, so a caller cannot silently use 0 or 100.
function Range.clamp(value)
    local number = asInteger(value)
    if number == nil then
        return Range.DEFAULT
    end
    if number < Range.MIN then
        return Range.MIN
    end
    if number > Range.MAX then
        return Range.MAX
    end
    return number
end

-- Tile steps between two squares, ignoring height. Both axes are in tiles.
function Range.chebyshev(fromX, fromY, toX, toY)
    return math.max(math.abs(fromX - toX), math.abs(fromY - toY))
end

local function coordinate(point, key)
    if type(point) ~= "table" then
        return nil
    end
    local value = point[key]
    if type(value) ~= "number" then
        return nil
    end
    return value
end

-- sorter and target are {x, y, z} in tiles. z is the floor (0 is ground,
-- negative is a basement). rangeTiles is the sandbox value; nil uses 20.
-- A tile exactly `range` steps away is inside. One step past that is not.
-- One floor up or down is inside. Two floors away is not, even at the
-- same x and y.
function Range.isInRange(sorter, target, rangeTiles)
    local sx = coordinate(sorter, "x")
    local sy = coordinate(sorter, "y")
    local sz = coordinate(sorter, "z")
    local tx = coordinate(target, "x")
    local ty = coordinate(target, "y")
    local tz = coordinate(target, "z")
    if not sx or not sy or not sz or not tx or not ty or not tz then
        return false
    end
    if math.abs(sz - tz) > Range.FLOOR_SPAN then
        return false
    end
    local range = Range.clamp(rangeTiles)
    return Range.chebyshev(sx, sy, tx, ty) <= range
end

-- The live sandbox option, still clamped to 20..30. Tests and a dedicated
-- server that has not loaded the option yet both get the default of 20.
function Range.current()
    local value = nil
    if SandboxVars and SandboxVars.PZSorter then
        value = SandboxVars.PZSorter.SorterRange
    end
    return Range.clamp(value)
end

return Range
