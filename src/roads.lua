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

-- Find nearest road tile to a given tile within maxRadius (Manhattan)
function roads.findNearestRoad(state, tx, ty, maxRadius)
  ensureState(state)
  maxRadius = maxRadius or 8
  if roads.hasRoad(state, tx, ty) then return tx, ty end
  for r = 1, maxRadius do
    for dy = -r, r do
      local dx = r - math.abs(dy)
      local candidates = {
        { tx + dx, ty + dy },
        { tx - dx, ty + dy }
      }
      for i = 1, #candidates do
        local x, y = candidates[i][1], candidates[i][2]
        if roads.hasRoad(state, x, y) then return x, y end
      end
    end
  end
  return nil, nil
end

-- BFS on road graph between two road tiles; returns list of tiles from start to end
local function bfsRoadPath(state, sx, sy, ex, ey)
  if not (sx and sy and ex and ey) then return nil end
  if sx == ex and sy == ey then return { { x = sx, y = sy } } end
  local q = { { sx, sy } }
  local head = 1
  local visited = {}
  local function K(x,y) return x .. "," .. y end
  visited[K(sx,sy)] = true
  local parent = {}
  local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
  while q[head] do
    local cx, cy = q[head][1], q[head][2]
    head = head + 1
    for i=1,4 do
      local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
      if not visited[K(nx,ny)] and roads.hasRoad(state, nx, ny) then
        visited[K(nx,ny)] = true
        parent[K(nx,ny)] = { cx, cy }
        if nx == ex and ny == ey then
          -- reconstruct
          local path = { { x = nx, y = ny } }
          local px, py = cx, cy
          while px and py do
            table.insert(path, 1, { x = px, y = py })
            local p = parent[K(px,py)]
            if not p then break end
            px, py = p[1], p[2]
          end
          return path
        end
        table.insert(q, { nx, ny })
      end
    end
  end
  return nil
end

-- Public: compute a list of world points along a road route between near-start and near-end
function roads.computeRoadRoute(state, startTileX, startTileY, endTileX, endTileY)
  local sx, sy = roads.findNearestRoad(state, startTileX, startTileY, 8)
  local ex, ey = roads.findNearestRoad(state, endTileX, endTileY, 8)
  if not (sx and sy and ex and ey) then return nil end
  local tilePath = bfsRoadPath(state, sx, sy, ex, ey)
  if not tilePath or #tilePath == 0 then return nil end
  local TILE = constants.TILE_SIZE
  local points = {}
  for i=1,#tilePath do
    local t = tilePath[i]
    table.insert(points, { x = t.x * TILE + TILE/2, y = t.y * TILE + TILE/2 })
  end
  return points
end

-- Check if a building occupies a tile
local function hasBuilding(state, x, y)
  for _, b in ipairs(state.game.buildings or {}) do
    if b.tileX == x and b.tileY == y then return true end
  end
  return false
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
  -- Snap endpoints to nearest placeable tiles to allow connecting to buildings
  local function snapToPlaceable(x, y)
    if roads.canPlaceAt(state, x, y) then return x, y end
    -- Try 4-neighbors; choose first placeable
    local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
    for i = 1, #dirs do
      local nx, ny = x + dirs[i][1], y + dirs[i][2]
      if roads.canPlaceAt(state, nx, ny) then return nx, ny end
    end
    return x, y
  end
  local originalStartBlocked = not roads.canPlaceAt(state, startX, startY)
  local sx, sy = snapToPlaceable(startX, startY)
  local ex, ey = snapToPlaceable(endX, endY)
  -- Build two candidate L paths and pick one that doesn't cross blocked tiles (e.g., buildings)
  local function pathIsClear(path)
    for i = 1, #path do
      local p = path[i]
      if roads.hasRoad(state, p.x, p.y) then
        -- allow existing roads as passable
      elseif not roads.canPlaceAt(state, p.x, p.y) then
        return false
      end
    end
    return true
  end
  -- Horizontal then vertical
  local hFirst = manhattanPath(sx, sy, ex, ey)
  if pathIsClear(hFirst) then
    if originalStartBlocked and roads.canPlaceAt(state, sx, sy) and not roads.hasRoad(state, sx, sy) then
      table.insert(hFirst, 1, { x = sx, y = sy })
    end
    return hFirst
  end
  -- Vertical then horizontal: swap axes by generating via intermediary
  local via = { x = sx, y = ey }
  local vFirst = {}
  do
    local x, y = sx, sy
    local dy = (ey > y) and 1 or -1
    while y ~= ey do
      y = y + dy
      table.insert(vFirst, { x = x, y = y })
    end
    local dx = (ex > x) and 1 or -1
    while x ~= ex do
      x = x + dx
      table.insert(vFirst, { x = x, y = y })
    end
  end
  if pathIsClear(vFirst) then
    if originalStartBlocked and roads.canPlaceAt(state, sx, sy) and not roads.hasRoad(state, sx, sy) then
      table.insert(vFirst, 1, { x = sx, y = sy })
    end
    return vFirst
  end
  -- fallback: return hFirst with start inclusion if needed
  if originalStartBlocked and roads.canPlaceAt(state, sx, sy) and not roads.hasRoad(state, sx, sy) then
    table.insert(hFirst, 1, { x = sx, y = sy })
  end
  return hFirst
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

    -- base tile (blend with grass background)
    love.graphics.setColor(0.16, 0.17, 0.18, 0.85)
    love.graphics.rectangle('fill', px + 2, py + 2, TILE - 4, TILE - 4, 4, 4)

    -- soft center strip
    love.graphics.setColor(0.20, 0.22, 0.22, 0.6)
    love.graphics.rectangle('fill', px + 6, py + TILE / 2 - 1, TILE - 12, 2, 1, 1)

    -- connections (very subtle extensions)
    love.graphics.setColor(0.15, 0.16, 0.17, 0.7)
    if has(state, x, y - 1) or hasBuilding(state, x, y - 1) then
      love.graphics.rectangle('fill', px + 6, py + 2, TILE - 12, TILE / 2 - 3)
    end
    if has(state, x + 1, y) or hasBuilding(state, x + 1, y) then
      love.graphics.rectangle('fill', cx + 2, py + 6, TILE / 2 - 4, TILE - 12)
    end
    if has(state, x, y + 1) or hasBuilding(state, x, y + 1) then
      love.graphics.rectangle('fill', px + 6, cy + 2, TILE - 12, TILE / 2 - 4)
    end
    if has(state, x - 1, y) or hasBuilding(state, x - 1, y) then
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