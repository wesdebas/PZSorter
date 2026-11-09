-- Which item goes to which container.
--
-- Pure Lua: no game calls. The server builds plain tables from the crate
-- and the linked containers, calls build, and then moves whatever build
-- decided. The tests run the same function. That is what keeps the in-game
-- sort from drifting away from the spec.
--
-- Rules, in the spec's order, for each item in the crate:
--   1. Skip equipped, favorited, and key items. A bag is one item. This
--      function never looks inside item.contents.
--   2. A container matches when it is here, in range, and its filter
--      accepts the item. An empty filter accepts nothing.
--   3. Most specific match wins. specificity 2 (this type ticked, category
--      not ticked) beats specificity 1 (the whole category, or a food
--      sub-group). Priority and overflow only compare containers that
--      tied on specificity.
--   4. Higher priority wins a tie (1 to 9, default 5). If priority is also
--      tied, the container closer to the crate wins. Distance is the same
--      square the range check uses (Chebyshev), then the floor gap.
--   5. If the item does not fit by weight or by an item-count cap, try the
--      next match in that same order.
--   6. Otherwise it stays in the crate. reason is "full" (named for the
--      best match) or "no_match". Skipped items stay too, with their own
--      reason, and they are not a failed match.

PZSorter = PZSorter or {}
PZSorter.SortPlan = PZSorter.SortPlan or {}

local Plan = PZSorter.SortPlan

require "PZSorter/Filter"
require "PZSorter/Range"
require "PZSorter/Links"

local Filter = PZSorter.Filter
local Range = PZSorter.Range
local Links = PZSorter.Links

-- maxTime units. A short vanilla grab is about 50, under a second. 100 units
-- is about one second at normal speed, before moodles stretch it. 50 items
-- with no extra weight is 1000 units: about 10 seconds, which is the timing
-- that was asked for. Weight adds a little, so a crate of engines takes
-- longer than a crate of paper. Instant mode is 1, which ends on the next tick.
Plan.PER_ITEM = 20
Plan.PER_WEIGHT = 2
Plan.SPEED_REALISTIC = "realistic"
Plan.SPEED_INSTANT = "instant"

local FAR = 1000000000

function Plan.normalizeSpeed(value)
    if value == Plan.SPEED_INSTANT or value == 2 or value == "2" then
        return Plan.SPEED_INSTANT
    end
    return Plan.SPEED_REALISTIC
end

-- The sandbox enum is 1 Realistic, 2 Instant. Missing means Realistic.
function Plan.currentSpeed()
    local value = nil
    if SandboxVars and SandboxVars.PZSorter then
        value = SandboxVars.PZSorter.SortSpeed
    end
    return Plan.normalizeSpeed(value)
end

function Plan.duration(count, totalWeight, speed)
    if Plan.normalizeSpeed(speed) == Plan.SPEED_INSTANT then
        return 1
    end
    count = tonumber(count) or 0
    if count < 0 then
        count = 0
    end
    count = math.floor(count)
    totalWeight = tonumber(totalWeight) or 0
    if totalWeight < 0 then
        totalWeight = 0
    end
    if count == 0 then
        return 1
    end
    local time = count * Plan.PER_ITEM + totalWeight * Plan.PER_WEIGHT
    if time < 1 then
        return 1
    end
    return math.floor(time)
end

local function distanceParts(origin, container)
    local ox = tonumber(origin and origin.x) or 0
    local oy = tonumber(origin and origin.y) or 0
    local oz = tonumber(origin and origin.z) or 0
    local cx = tonumber(container.x)
    local cy = tonumber(container.y)
    local cz = tonumber(container.z)
    if not cx or not cy or not cz then
        return FAR, FAR
    end
    return Range.chebyshev(ox, oy, cx, cy), math.abs(oz - cz)
end

local function usable(container)
    if type(container) ~= "table" then
        return false
    end
    if container.missing then
        return false
    end
    if container.inRange == false then
        return false
    end
    -- The ground is a container whose type is "floor". It is not a place
    -- we sort into. The item stays in the crate instead.
    if container.floor or container.type == "floor" then
        return false
    end
    return true
end

-- Weight is the container capacity. maxItems is an optional count cap, for
-- a container that also runs out of slots. Either one is enough to overflow.
local function fits(container, item, state)
    local added = tonumber(item.weight) or 0
    if added < 0 then
        added = 0
    end
    local capacity = tonumber(container.capacity)
    if capacity and state.weight + added > capacity + 0.0001 then
        return false
    end
    local maxItems = tonumber(container.maxItems)
    if maxItems and state.itemCount + 1 > maxItems then
        return false
    end
    return true
end

local function leave(steps, leftovers, item, reason, container)
    local step = {
        action = "leave",
        itemId = item.id,
        reason = reason,
    }
    if container then
        step.containerId = container.id
        step.containerName = container.name
    end
    steps[#steps + 1] = step
    leftovers[#leftovers + 1] = step
    return step
end

local function copyRanked(ranked)
    local copy = {}
    for i = 1, #ranked do
        copy[i] = { id = ranked[i].id, name = ranked[i].name }
    end
    return copy
end

function Plan.build(input)
    local steps = {}
    local moves = {}
    local leftovers = {}
    if type(input) ~= "table" then
        return { steps = steps, moves = moves, leftovers = leftovers }
    end
    local origin = input.sorter
    local items = input.items
    local containers = input.containers
    if type(items) ~= "table" then
        items = {}
    end
    if type(containers) ~= "table" then
        containers = {}
    end

    -- Copy fill levels. The caller's tables stay as they were, so a retry
    -- can build again from the same snapshot.
    local state = {}
    local usableContainers = {}
    for i = 1, #containers do
        local container = containers[i]
        if usable(container) then
            usableContainers[#usableContainers + 1] = container
            state[container] = {
                weight = tonumber(container.weight) or 0,
                itemCount = tonumber(container.itemCount) or 0,
            }
        end
    end

    for index = 1, #items do
        local item = items[index]
        if type(item) == "table" then
            if item.equipped then
                leave(steps, leftovers, item, "equipped", nil)
            elseif item.favorited then
                leave(steps, leftovers, item, "favorited", nil)
            elseif item.key then
                leave(steps, leftovers, item, "key", nil)
            else
                local ranked = {}
                for c = 1, #usableContainers do
                    local container = usableContainers[c]
                    local specificity = Filter.specificity(container.filter, item)
                    if specificity > 0 then
                        local horizontal, floorGap = distanceParts(origin, container)
                        ranked[#ranked + 1] = {
                            container = container,
                            id = container.id,
                            name = container.name,
                            specificity = specificity,
                            priority = Links.clampPriority(container.priority),
                            horizontal = horizontal,
                            floorGap = floorGap,
                        }
                    end
                end
                table.sort(ranked, function(a, b)
                    if a.specificity ~= b.specificity then
                        return a.specificity > b.specificity
                    end
                    if a.priority ~= b.priority then
                        return a.priority > b.priority
                    end
                    if a.horizontal ~= b.horizontal then
                        return a.horizontal < b.horizontal
                    end
                    if a.floorGap ~= b.floorGap then
                        return a.floorGap < b.floorGap
                    end
                    if tostring(a.name) ~= tostring(b.name) then
                        return tostring(a.name) < tostring(b.name)
                    end
                    return tostring(a.id) < tostring(b.id)
                end)

                local chosen = nil
                for r = 1, #ranked do
                    local container = ranked[r].container
                    if fits(container, item, state[container]) then
                        chosen = ranked[r]
                        break
                    end
                end
                local rankedCopy = copyRanked(ranked)
                if chosen then
                    local container = chosen.container
                    local added = tonumber(item.weight) or 0
                    if added < 0 then
                        added = 0
                    end
                    state[container].weight = state[container].weight + added
                    state[container].itemCount = state[container].itemCount + 1
                    local step = {
                        action = "move",
                        itemId = item.id,
                        containerId = chosen.id,
                        containerName = chosen.name,
                        ranked = rankedCopy,
                    }
                    steps[#steps + 1] = step
                    moves[#moves + 1] = step
                elseif #ranked > 0 then
                    local step = leave(steps, leftovers, item, "full", ranked[1].container)
                    step.ranked = rankedCopy
                else
                    local step = leave(steps, leftovers, item, "no_match", nil)
                    step.ranked = rankedCopy
                end
            end
        end
    end

    return { steps = steps, moves = moves, leftovers = leftovers }
end

local function reasonLabel(entry)
    if entry.reason == "full" then
        if type(entry.containerName) == "string" and entry.containerName ~= "" then
            return entry.containerName .. " full"
        end
        return "full"
    end
    if entry.reason == "no_match" then
        return "no match"
    end
    if entry.reason == "equipped" or entry.reason == "favorited" or entry.reason == "key" then
        return entry.reason
    end
    if type(entry.reason) == "string" and entry.reason ~= "" then
        return entry.reason
    end
    return "no match"
end

-- "Sorted 38 items. 4 left: Freezer 1 full (3), no match (1)."
-- Groups follow the order the leftovers were decided, so the container the
-- item tried first is the one named in a "full" clause.
function Plan.summary(result)
    local moves = {}
    local leftovers = {}
    if type(result) == "table" then
        if type(result.moves) == "table" then
            moves = result.moves
        end
        if type(result.leftovers) == "table" then
            leftovers = result.leftovers
        end
    end
    local sorted = #moves
    local itemWord = "items"
    if sorted == 1 then
        itemWord = "item"
    end
    local head = "Sorted " .. tostring(sorted) .. " " .. itemWord .. "."
    if #leftovers == 0 then
        return head
    end
    local groups = {}
    local order = {}
    for i = 1, #leftovers do
        local entry = leftovers[i]
        if type(entry) == "table" then
            local label = reasonLabel(entry)
            if not groups[label] then
                groups[label] = 0
                order[#order + 1] = label
            end
            groups[label] = groups[label] + 1
        end
    end
    if #order == 0 then
        return head
    end
    local parts = {}
    local left = 0
    for i = 1, #order do
        local label = order[i]
        local count = groups[label]
        left = left + count
        parts[#parts + 1] = label .. " (" .. tostring(count) .. ")"
    end
    return head .. " " .. tostring(left) .. " left: " .. table.concat(parts, ", ") .. "."
end

return Plan
