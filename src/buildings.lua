-- buildings.lua
-- Placement rules, building rendering and radii drawing

local constants = require('src.constants')
local trees = require('src.trees')
local utils = require('src.utils')
local particles = require('src.particles')
local colors = constants.colors

local buildings = {}

function buildings.canAfford(state, buildingType)
  local def = state.buildingDefs[buildingType]
  if not def or not def.cost then return true end
  for resourceName, amount in pairs(def.cost) do
    local current = state.game.resources[resourceName] or 0
    if current < amount then return false end
  end
  return true
end

function buildings.payCost(state, buildingType)
  local def = state.buildingDefs[buildingType]
  if not def or not def.cost then return end
  for resourceName, amount in pairs(def.cost) do
    local current = state.game.resources[resourceName] or 0
    state.game.resources[resourceName] = math.max(0, current - amount)
  end
end

function buildings.canPlaceAt(state, tileX, tileY)
  local world = state.world
  if tileX < 0 or tileY < 0 or tileX >= world.tilesX or tileY >= world.tilesY then
    return false
  end
  for _, b in ipairs(state.game.buildings) do
    if b.tileX == tileX and b.tileY == tileY then
      return false
    end
  end
  if trees.getAt(state, tileX, tileY) then
    return false
  end
  return true
end

function buildings.place(state, buildingType, tileX, tileY)
  local color
  if buildingType == "house" then
    color = { 0.9, 0.6, 0.2, 1.0 }
  elseif buildingType == "lumberyard" then
    color = { 0.3, 0.7, 0.3, 1.0 }
  else
    color = { 0.7, 0.7, 0.7, 1.0 }
  end
  local newB = {
    type = buildingType,
    tileX = tileX,
    tileY = tileY,
    color = color,
    anim = { appear = 0, t = 0, sawAngle = 0, active = false }
  }
  table.insert(state.game.buildings, newB)

  -- dust burst on placement
  local TILE_SIZE = constants.TILE_SIZE
  local px = tileX * TILE_SIZE + TILE_SIZE / 2
  local py = tileY * TILE_SIZE + TILE_SIZE / 2
  particles.spawnDustBurst(state.game.particles, px, py)

  return newB
end

-- Update simple building animations
function buildings.update(state, dt)
  for _, b in ipairs(state.game.buildings) do
    b.anim = b.anim or { appear = 1, t = 0, sawAngle = 0, active = false }
    -- Appear tween
    if b.anim.appear < 1 then
      b.anim.appear = math.min(1, b.anim.appear + dt * 3.0)
    end
    -- Idle breathing
    b.anim.t = (b.anim.t or 0) + dt

    -- Lumberyard active indicator (rotating saw) if any worker is busy
    if b.type == 'lumberyard' and b.workers then
      local active = false
      for _, w in ipairs(b.workers) do
        if w.state == 'toTree' or w.state == 'chopping' or w.state == 'returning' then
          active = true
          break
        end
      end
      b.anim.active = active
      if active then
        b.anim.sawAngle = (b.anim.sawAngle or 0) + dt * 6.0
      end
    end
  end
end

-- Draw a simple saw blade icon at given position
local function drawSaw(cx, cy, angle)
  local r = 6
  love.graphics.setColor(colors.outline)
  love.graphics.circle('line', cx, cy, r)
  for i = 0, 5 do
    local a = angle + i * (math.pi * 2 / 6)
    local x1 = cx + math.cos(a) * (r - 2)
    local y1 = cy + math.sin(a) * (r - 2)
    local x2 = cx + math.cos(a) * (r + 2)
    local y2 = cy + math.sin(a) * (r + 2)
    love.graphics.line(x1, y1, x2, y2)
  end
end

function buildings.drawAll(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, b in ipairs(state.game.buildings) do
    local px = b.tileX * TILE_SIZE
    local py = b.tileY * TILE_SIZE
    local cx = px + TILE_SIZE / 2
    local cy = py + TILE_SIZE / 2

    -- shadow
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.ellipse('fill', cx, py + TILE_SIZE * 0.9, TILE_SIZE * 0.35, TILE_SIZE * 0.18)

    -- Compute animated scale: appear tween and subtle breathing
    local appear = (b.anim and b.anim.appear) or 1
    local t = (b.anim and b.anim.t) or 0
    local breath = 1 + 0.02 * math.sin(t * 3.0)
    local scale = (0.9 + 0.1 * appear) * breath

    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(scale, scale)
    love.graphics.setColor(b.color)
    love.graphics.rectangle("fill", -TILE_SIZE / 2, -TILE_SIZE / 2, TILE_SIZE, TILE_SIZE, 4, 4)
    love.graphics.setColor(colors.outline)
    love.graphics.rectangle("line", -TILE_SIZE / 2, -TILE_SIZE / 2, TILE_SIZE, TILE_SIZE, 4, 4)

    -- Building-specific visuals
    if b.type == 'lumberyard' then
      if b.anim and b.anim.active then
        local r = 6
        local angle = (b.anim.sawAngle or 0)
        love.graphics.setColor(colors.outline)
        love.graphics.circle('line', 0, -TILE_SIZE * 0.35, r)
        for i = 0, 5 do
          local a = angle + i * (math.pi * 2 / 6)
          local x1 = math.cos(a) * (r - 2)
          local y1 = -TILE_SIZE * 0.35 + math.sin(a) * (r - 2)
          local x2 = math.cos(a) * (r + 2)
          local y2 = -TILE_SIZE * 0.35 + math.sin(a) * (r + 2)
          love.graphics.line(x1, y1, x2, y2)
        end
      end
    elseif b.type == 'house' then
      local a = 0.3 + 0.2 * (0.5 + 0.5 * math.sin(t * 2.2))
      love.graphics.setColor(1.0, 0.95, 0.7, a)
      love.graphics.rectangle('fill', -TILE_SIZE * 0.15, -TILE_SIZE * 0.05, TILE_SIZE * 0.2, TILE_SIZE * 0.2, 2, 2)
    end

    love.graphics.pop()
  end
end

-- Draw selected building radius (lumberyard only)
function buildings.drawSelectedRadius(state)
  local TILE_SIZE = constants.TILE_SIZE
  local b = state.ui.selectedBuilding
  if not b or b.type ~= 'lumberyard' then return end
  local def = state.buildingDefs.lumberyard
  local radiusPx = def.radiusTiles * TILE_SIZE
  local cx = b.tileX * TILE_SIZE + TILE_SIZE / 2
  local cy = b.tileY * TILE_SIZE + TILE_SIZE / 2

  for i = 1, 5 do
    local t = i / 5
    love.graphics.setColor(colors.radius[1], colors.radius[2], colors.radius[3], colors.radius[4] * (1 - t))
    love.graphics.circle('line', cx, cy, radiusPx * (1 - t * 0.08))
  end
  love.graphics.setColor(colors.radiusOutline)
  love.graphics.circle('line', cx, cy, radiusPx)
end

return buildings