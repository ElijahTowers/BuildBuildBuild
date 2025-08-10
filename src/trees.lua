-- trees.lua
-- Tree generation, rendering and chop-shake helpers

local constants = require('src.constants')
local utils = require('src.utils')
local colors = constants.colors

local trees = {}

function trees.generate(state)
  local TILE_SIZE = constants.TILE_SIZE
  local world = state.world
  local list = {}

  local tilesX = world.tilesX
  local tilesY = world.tilesY
  local clusterCount = 48
  local minClusterSize, maxClusterSize = 8, 22
  local clusterSpreadTiles = 5

  local occupied = {}
  local function key(x, y) return x .. "," .. y end

  for _ = 1, clusterCount do
    local cx = math.random(2, tilesX - 3)
    local cy = math.random(3, tilesY - 3)
    local clusterSize = math.random(minClusterSize, maxClusterSize)

    for _ = 1, clusterSize do
      local ox = math.random(-clusterSpreadTiles, clusterSpreadTiles)
      local oy = math.random(-clusterSpreadTiles, clusterSpreadTiles)
      local tx = math.max(0, math.min(tilesX - 1, cx + ox))
      local ty = math.max(0, math.min(tilesY - 1, cy + oy))
      local k = key(tx, ty)
      if not occupied[k] then
        occupied[k] = true
        table.insert(list, { tileX = tx, tileY = ty, alive = true, health = 3.0, reserved = false, beingChopped = false, shakeTime = 0, shakePower = 0, shakeDirX = 0, shakeDirY = 0 })
      end
    end
  end

  state.game.trees = list
end

function trees.getAt(state, tileX, tileY)
  for index, t in ipairs(state.game.trees) do
    if t.alive and t.tileX == tileX and t.tileY == tileY then
      return index
    end
  end
  return nil
end

function trees.updateShake(state, dt)
  for _, t in ipairs(state.game.trees) do
    if (t.shakePower or 0) > 0 then
      t.shakeTime = (t.shakeTime or 0) + dt
      t.shakePower = math.max(0, (t.shakePower or 0) - 3.0 * dt)
    end
  end
end

function trees.getShakeOffset(t)
  local power = t.shakePower or 0
  if power <= 0 then return 0, 0 end
  local freq = 35
  local osc = math.sin((t.shakeTime or 0) * freq)
  return osc * power * (t.shakeDirX or 0), osc * power * (t.shakeDirY or 0)
end

function trees.draw(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, t in ipairs(state.game.trees) do
    if t.alive then
      local cx = t.tileX * TILE_SIZE + TILE_SIZE / 2
      local cy = t.tileY * TILE_SIZE + TILE_SIZE / 2
      local r = TILE_SIZE * 0.4
      local sx, sy = trees.getShakeOffset(t)

      -- shadow
      love.graphics.setColor(0, 0, 0, 0.22)
      love.graphics.ellipse('fill', cx, cy + TILE_SIZE * 0.18, r, r * 0.35)

      local beingChopped = t.beingChopped
      if beingChopped then
        love.graphics.setColor(colors.treeFill[1], colors.treeFill[2], colors.treeFill[3], 0.8)
      else
        love.graphics.setColor(colors.treeFill)
      end
      love.graphics.circle("fill", cx + sx, cy + sy, r)
      love.graphics.setColor(colors.treeOutline)
      love.graphics.circle("line", cx + sx, cy + sy, r)

      if beingChopped then
        love.graphics.setColor(colors.choppingRing)
        love.graphics.circle("line", cx, cy, r + 6)
      end
    end
  end
end

return trees 