-- trees.lua
-- Tree generation, rendering and chop-shake helpers

local constants = require('src.constants')
local utils = require('src.utils')
local colors = constants.colors

local trees = {}

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

local function mulColor(c, m)
  return { clamp01(c[1] * m), clamp01(c[2] * m), clamp01(c[3] * m), c[4] or 1 }
end

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
        table.insert(list, {
          tileX = tx,
          tileY = ty,
          alive = true,
          health = 3.0,
          reserved = false,
          beingChopped = false,
          shakeTime = 0,
          shakePower = 0,
          shakeDirX = 0,
          shakeDirY = 0,
          sizeScale = 0.9 + math.random() * 0.25,
          colorMul = 0.9 + math.random() * 0.2,
          windPhase = math.random() * math.pi * 2,
          windTime = 0,
          stumpTime = 0
        })
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
    -- gentle wind sway time
    t.windTime = (t.windTime or 0) + dt
    -- stump timer decay
    if (t.stumpTime or 0) > 0 then
      t.stumpTime = math.max(0, t.stumpTime - dt)
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

local function getWindOffset(t)
  local a = (t.windTime or 0) * 1.3 + (t.windPhase or 0)
  local x = math.sin(a) * 3
  local y = math.cos(a * 0.7) * 1.2
  return x, y
end

function trees.draw(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, t in ipairs(state.game.trees) do
    local cx = t.tileX * TILE_SIZE + TILE_SIZE / 2
    local cy = t.tileY * TILE_SIZE + TILE_SIZE / 2

    -- Draw stump if recently felled
    if (not t.alive) and (t.stumpTime or 0) > 0 then
      local stumpAlpha = math.min(1, t.stumpTime / 3.0)
      local stumpR = TILE_SIZE * 0.18
      love.graphics.setColor(0.45, 0.32, 0.2, 0.9 * stumpAlpha)
      love.graphics.ellipse('fill', cx, cy + TILE_SIZE * 0.22, stumpR, stumpR * 0.5)
      love.graphics.setColor(0.65, 0.5, 0.3, 0.8 * stumpAlpha)
      love.graphics.circle('fill', cx, cy + TILE_SIZE * 0.12, stumpR * 0.8)
      love.graphics.setColor(0.3, 0.22, 0.14, 0.8 * stumpAlpha)
      love.graphics.circle('line', cx, cy + TILE_SIZE * 0.12, stumpR * 0.8)
      -- rings
      love.graphics.setColor(0.55, 0.42, 0.28, 0.6 * stumpAlpha)
      love.graphics.circle('line', cx, cy + TILE_SIZE * 0.12, stumpR * 0.55)
      love.graphics.circle('line', cx, cy + TILE_SIZE * 0.12, stumpR * 0.3)
      goto continue
    end

    if t.alive then
      local baseR = TILE_SIZE * 0.4
      local r = baseR * (t.sizeScale or 1)
      local sx, sy = trees.getShakeOffset(t)
      local wx, wy = getWindOffset(t)
      local ox = sx + wx
      local oy = sy + wy

      -- shadow
      love.graphics.setColor(0, 0, 0, 0.22)
      love.graphics.ellipse('fill', cx, cy + TILE_SIZE * 0.18, r, r * 0.35)

      -- trunk
      local trunkW = TILE_SIZE * 0.12 * (t.sizeScale or 1)
      local trunkH = TILE_SIZE * 0.28 * (t.sizeScale or 1)
      love.graphics.setColor(0.35, 0.25, 0.18, 1)
      love.graphics.rectangle('fill', cx - trunkW / 2, cy + r * 0.05, trunkW, trunkH, 2, 2)
      love.graphics.setColor(0.22, 0.16, 0.12, 0.8)
      love.graphics.rectangle('line', cx - trunkW / 2, cy + r * 0.05, trunkW, trunkH, 2, 2)

      -- foliage (three overlapping circles)
      local foliageColor = mulColor(colors.treeFill, (t.colorMul or 1))
      love.graphics.setColor(foliageColor)
      love.graphics.circle('fill', cx + ox, cy + oy - r * 0.15, r)
      love.graphics.circle('fill', cx + ox - r * 0.35, cy + oy - r * 0.05, r * 0.8)
      love.graphics.circle('fill', cx + ox + r * 0.35, cy + oy - r * 0.05, r * 0.8)

      -- highlight
      love.graphics.setColor(1, 1, 1, 0.08)
      love.graphics.circle('fill', cx + ox - r * 0.25, cy + oy - r * 0.35, r * 0.35)

      -- outline
      love.graphics.setColor(colors.treeOutline)
      love.graphics.circle('line', cx + ox, cy + oy - r * 0.15, r)

      -- chopping indicator
      if t.beingChopped then
        love.graphics.setColor(colors.choppingRing)
        love.graphics.circle('line', cx, cy, r + 6)
      end
    end

    ::continue::
  end
end

return trees 