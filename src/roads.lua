-- roads.lua
-- Road system: data, placement (click-drag), preview path and rendering

local constants = require('src.constants')
local utils = require('src.utils')
local colors = constants.colors

local roads = {}

-- Internal: key for map lookup
local function key(x, y) return x .. "," .. y end

-- Ensure roads table exists in state
local function ensureState(state)
  state.game.roads = state.game.roads or {}
  state.game.roadsUsage = state.game.roadsUsage or {}
end

-- Sum total wood across base and warehouses
local function computeTotalWood(state)
  local total = state.game.resources.wood or 0
  for _, b in ipairs(state.game.buildings or {}) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      total = total + b.storage.wood
    end
  end
  return total
end

-- Pay wood cost, draining base first then warehouses
local function payWood(state, amount)
  local remain = amount
  local base = state.game.resources.wood or 0
  local take = math.min(base, remain)
  state.game.resources.wood = base - take
  remain = remain - take
  if remain > 0 then
    for _, b in ipairs(state.game.buildings or {}) do
      if remain <= 0 then break end
      if b.type == 'warehouse' then
        b.storage = b.storage or {}
        local w = b.storage.wood or 0
        local t = math.min(w, remain)
        b.storage.wood = w - t
        remain = remain - t
      end
    end
  end
end

function roads.hasRoad(state, x, y)
  ensureState(state)
  return state.game.roads[key(x, y)] ~= nil
end

function roads.markUsed(state, x, y)
  ensureState(state)
  local k = key(x, y)
  state.game.roadsUsage[k] = math.min(1.0, (state.game.roadsUsage[k] or 0) + 0.5)
end

function roads.update(state, dt)
  ensureState(state)
  local decay = 1.5 * dt
  for k, v in pairs(state.game.roadsUsage) do
    v = v - decay
    if v <= 0 then state.game.roadsUsage[k] = nil else state.game.roadsUsage[k] = v end
  end
end

-- Bounds and collisions (no buildings or trees on tile)
function roads.canPlaceAt(state, x, y)
  if x < 0 or y < 0 or x >= state.world.tilesX or y >= state.world.tilesY then return false end
  -- No buildings on tile
  for _, b in ipairs(state.game.buildings) do
    if b.tileX == x and b.tileY == y then return false end
  end
  -- No trees on tile
  for _, t in ipairs(state.game.trees) do
    if t.alive and t.tileX == x and t.tileY == y then return false end
  end
  -- Allow placing over existing road? No (skip duplicates in path)
  return true
end

-- Simple Manhattan L-shaped path: horizontal then vertical
local function manhattanPath(x1, y1, x2, y2)
  local path = {}
  local x, y = x1, y1
  local dx = x2 > x and 1 or -1
  local dy = y2 > y and 1 or -1
  while x ~= x2 do
    x = x + dx
    table.insert(path, { x = x, y = y })
  end
  while y ~= y2 do
    y = y + dy
    table.insert(path, { x = x, y = y })
  end
  return path
end

-- Compute preview/build path from start to end (excludes start tile)
function roads.computePath(state, startX, startY, endX, endY)
  if not startX or not startY or not endX or not endY then return {} end
  if startX == endX and startY == endY then return {} end
  return manhattanPath(startX, startY, endX, endY)
end

-- Count placeable tiles and affordability
local function countPlaceableAndAffordable(state, path)
  local costPer = (state.buildingDefs.road.costPerTile and state.buildingDefs.road.costPerTile.wood) or 0
  local totalWood = computeTotalWood(state)
  local affordableTiles = costPer > 0 and math.floor(totalWood / costPer) or #path
  local count = 0
  for i = 1, #path do
    local p = path[i]
    if roads.hasRoad(state, p.x, p.y) then
      -- skip, already exists, do not count
    elseif roads.canPlaceAt(state, p.x, p.y) then
      count = count + 1
    else
      -- blocked; stop path here
      break
    end
  end
  return math.min(count, affordableTiles)
end

function roads.placePath(state, path)
  ensureState(state)
  local costPer = (state.buildingDefs.road.costPerTile and state.buildingDefs.road.costPerTile.wood) or 0
  local placeCount = countPlaceableAndAffordable(state, path)
  local placed = 0
  for i = 1, placeCount do
    local p = path[i]
    if not roads.hasRoad(state, p.x, p.y) and roads.canPlaceAt(state, p.x, p.y) then
      state.game.roads[key(p.x, p.y)] = { tileX = p.x, tileY = p.y }
      placed = placed + 1
    end
  end
  if placed > 0 and costPer > 0 then
    payWood(state, placed * costPer)
  end
  if placed > 0 then return true, placed else return false, 0 end
end

-- Draw roads with neighbor connections (subtle look)
local function has(state, x, y) return roads.hasRoad(state, x, y) end

function roads.draw(state)
  ensureState(state)
  local TILE = constants.TILE_SIZE
  for _, rd in pairs(state.game.roads) do
    local x = rd.tileX
    local y = rd.tileY
    local px = x * TILE
    local py = y * TILE
    local cx = px + TILE / 2
    local cy = py + TILE / 2

    -- base tile (blend with background)
    love.graphics.setColor(0.18, 0.18, 0.20, 0.85)
    love.graphics.rectangle('fill', px + 2, py + 2, TILE - 4, TILE - 4, 4, 4)

    -- soft center strip
    love.graphics.setColor(0.22, 0.22, 0.24, 0.6)
    love.graphics.rectangle('fill', px + 6, py + TILE / 2 - 1, TILE - 12, 2, 1, 1)

    -- connections (very subtle extensions)
    love.graphics.setColor(0.16, 0.16, 0.18, 0.7)
    if has(state, x, y - 1) then
      love.graphics.rectangle('fill', px + 6, py + 2, TILE - 12, TILE / 2 - 3)
    end
    if has(state, x + 1, y) then
      love.graphics.rectangle('fill', cx + 2, py + 6, TILE / 2 - 4, TILE - 12)
    end
    if has(state, x, y + 1) then
      love.graphics.rectangle('fill', px + 6, cy + 2, TILE - 12, TILE / 2 - 4)
    end
    if has(state, x - 1, y) then
      love.graphics.rectangle('fill', px + 2, py + 6, TILE / 2 - 3, TILE - 12)
    end

    -- usage glow
    local u = state.game.roadsUsage[key(x, y)] or 0
    if u > 0 then
      love.graphics.setColor(1.0, 1.0, 0.6, 0.25 * u)
      love.graphics.rectangle('fill', px + 2, py + 2, TILE - 4, TILE - 4, 6, 6)
      love.graphics.setColor(1.0, 0.95, 0.5, 0.3 * u)
      love.graphics.rectangle('line', px + 2, py + 2, TILE - 4, TILE - 4, 6, 6)
    end

    -- outline (low alpha)
    love.graphics.setColor(colors.outline[1], colors.outline[2], colors.outline[3], 0.12)
    love.graphics.rectangle('line', px + 2, py + 2, TILE - 4, TILE - 4, 4, 4)
  end
end

-- Draw preview path from start to current mouse tile
function roads.drawPreview(state, path)
  if not path or #path == 0 then return end
  local TILE = constants.TILE_SIZE
  local validCount = countPlaceableAndAffordable(state, path)
  for i, p in ipairs(path) do
    local px = p.x * TILE
    local py = p.y * TILE
    local valid = i <= validCount and roads.canPlaceAt(state, p.x, p.y) and not roads.hasRoad(state, p.x, p.y)
    love.graphics.setColor(valid and colors.preview or colors.invalid)
    love.graphics.rectangle('fill', px, py, TILE, TILE, 4, 4)
    love.graphics.setColor(colors.outline)
    love.graphics.rectangle('line', px, py, TILE, TILE, 4, 4)
  end
end

return roads 