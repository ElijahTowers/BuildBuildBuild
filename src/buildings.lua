-- buildings.lua
-- Placement rules, building rendering and radii drawing

local constants = require('src.constants')
local trees = require('src.trees')
local utils = require('src.utils')
local particles = require('src.particles')
local colors = constants.colors
local workers = require('src.workers')

local buildings = {}

function buildings.canAfford(state, buildingType)
  local def = state.buildingDefs[buildingType]
  if not def or not def.cost then return true end
  local neededWood = def.cost.wood or 0
  if neededWood <= 0 then return true end
  local base = state.game.resources.wood or 0
  local stored = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      stored = stored + b.storage.wood
    end
  end
  return (base + stored) >= neededWood
end

function buildings.payCost(state, buildingType)
  local def = state.buildingDefs[buildingType]
  if not def or not def.cost then return end
  local neededWood = def.cost.wood or 0
  if neededWood > 0 then
    local base = state.game.resources.wood or 0
    local takeFromBase = math.min(base, neededWood)
    state.game.resources.wood = base - takeFromBase
    local remaining = neededWood - takeFromBase
    if remaining > 0 then
      for _, b in ipairs(state.game.buildings) do
        if remaining <= 0 then break end
        if b.type == 'warehouse' then
          b.storage = b.storage or {}
          local w = b.storage.wood or 0
          local take = math.min(w, remaining)
          b.storage.wood = w - take
          remaining = remaining - take
        end
      end
    end
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
  return true
end

function buildings.place(state, buildingType, tileX, tileY)
  trees.removeAt(state, tileX, tileY)
  local def = state.buildingDefs[buildingType]
  local color = { 0.7, 0.7, 0.7, 1.0 }
  if buildingType == 'house' then color = { 0.9, 0.6, 0.2, 1.0 }
  elseif buildingType == 'lumberyard' then color = { 0.3, 0.7, 0.3, 1.0 }
  elseif buildingType == 'warehouse' then color = { 0.6, 0.6, 0.7, 1.0 }
  elseif buildingType == 'builder' then color = { 0.7, 0.5, 0.3, 1.0 }
  end
  local newB = {
    type = buildingType,
    tileX = tileX,
    tileY = tileY,
    color = color,
    anim = { appear = 0, t = 0, sawAngle = 0, active = false },
    assigned = 0,
    currentResidents = 0,
    storage = { wood = 0 },
    construction = {
      required = (def and def.buildRequired) or 10,
      progress = 0,
      complete = (buildingType == 'house' and false) or false
    }
  }
  -- Buildings start under construction unless builder itself? Keep builder also needs construction
  table.insert(state.game.buildings, newB)

  if buildingType == 'house' then
    local cap = (state.buildingDefs.house.residents or 0)
    state.game.population.capacity = (state.game.population.capacity or 0) + cap
  elseif buildingType == 'builder' then
    local cap = (state.buildingDefs.builder.residents or 0)
    state.game.population.capacity = (state.game.population.capacity or 0) + cap
  end

  local TILE = constants.TILE_SIZE
  local px = tileX * TILE + TILE / 2
  local py = tileY * TILE + TILE / 2
  particles.spawnDustBurst(state.game.particles, px, py)

  return newB
end

function buildings.update(state, dt)
  for _, b in ipairs(state.game.buildings) do
    b.anim = b.anim or { appear = 1, t = 0, sawAngle = 0, active = false }
    if b.anim.appear < 1 then b.anim.appear = math.min(1, b.anim.appear + dt * 3.0) end
    b.anim.t = (b.anim.t or 0) + dt

    if b.type == 'lumberyard' then
      b.anim.active = (b.assigned or 0) > 0
    end
  end
end

function buildings.assignOne(state, b)
  if b.type == 'lumberyard' then
    local free = (state.game.population.total or 0) - (state.game.population.assigned or 0)
    local maxSlots = state.buildingDefs.lumberyard.numWorkers or 0
    if free <= 0 or (b.assigned or 0) >= maxSlots then return false end
    b.assigned = (b.assigned or 0) + 1
    state.game.population.assigned = (state.game.population.assigned or 0) + 1
    workers.spawnAssignedWorker(state, b)
    return true
  elseif b.type == 'builder' then
    local free = (state.game.population.total or 0) - (state.game.population.assigned or 0)
    local maxSlots = state.buildingDefs.builder.numWorkers or 0
    if free <= 0 or (b.assigned or 0) >= maxSlots then return false end
    b.assigned = (b.assigned or 0) + 1
    state.game.population.assigned = (state.game.population.assigned or 0) + 1
    -- spawn a generic villager that idles at builder workplace (reuse workers.spawnAssignedWorker with work b itself)
    workers.spawnAssignedWorker(state, b)
    return true
  end
  return false
end

function buildings.unassignOne(state, b)
  if b.type ~= 'lumberyard' and b.type ~= 'builder' then return false end
  if (b.assigned or 0) <= 0 then return false end
  b.assigned = b.assigned - 1
  state.game.population.assigned = state.game.population.assigned - 1
  return true
end

function buildings.drawAll(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, b in ipairs(state.game.buildings) do
    local px = b.tileX * TILE_SIZE
    local py = b.tileY * TILE_SIZE
    local cx = px + TILE_SIZE / 2
    local cy = py + TILE_SIZE / 2

    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.ellipse('fill', cx, py + TILE_SIZE * 0.9, TILE_SIZE * 0.35, TILE_SIZE * 0.18)

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

    if b.type == 'warehouse' then
      love.graphics.setColor(0.45, 0.4, 0.35, 1)
      love.graphics.rectangle('fill', -TILE_SIZE * 0.18, TILE_SIZE * 0.05, TILE_SIZE * 0.36, TILE_SIZE * 0.28, 2, 2)
      love.graphics.setColor(0.65, 0.5, 0.3, 1)
      love.graphics.rectangle('fill', -TILE_SIZE * 0.12, -TILE_SIZE * 0.1, TILE_SIZE * 0.24, TILE_SIZE * 0.12)
    elseif b.type == 'lumberyard' then
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
      love.graphics.setColor(0.3, 0.3, 0.35, 1)
      love.graphics.rectangle('fill', TILE_SIZE * 0.18, -TILE_SIZE * 0.5 - TILE_SIZE * 0.35 + 6, 6, 10)
    elseif b.type == 'builder' then
      love.graphics.setColor(0.5, 0.4, 0.2, 1)
      love.graphics.rectangle('fill', -TILE_SIZE * 0.2, -TILE_SIZE * 0.05, TILE_SIZE * 0.4, TILE_SIZE * 0.25)
      love.graphics.setColor(colors.outline)
      love.graphics.rectangle('line', -TILE_SIZE * 0.2, -TILE_SIZE * 0.05, TILE_SIZE * 0.4, TILE_SIZE * 0.25)
      love.graphics.setColor(0.7, 0.6, 0.3, 1)
      love.graphics.rectangle('fill', -TILE_SIZE * 0.1, -TILE_SIZE * 0.25, TILE_SIZE * 0.2, TILE_SIZE * 0.15)
    end

    -- Construction progress bar
    if b.construction and not b.construction.complete then
      local p = (b.construction.progress or 0) / (b.construction.required or 1)
      love.graphics.setColor(0, 0, 0, 0.5)
      love.graphics.rectangle('fill', -TILE_SIZE / 2, TILE_SIZE * 0.45, TILE_SIZE, 6, 3, 3)
      love.graphics.setColor(0.2, 0.8, 0.3, 1)
      love.graphics.rectangle('fill', -TILE_SIZE / 2, TILE_SIZE * 0.45, TILE_SIZE * p, 6, 3, 3)
      love.graphics.setColor(colors.outline)
      love.graphics.rectangle('line', -TILE_SIZE / 2, TILE_SIZE * 0.45, TILE_SIZE, 6, 3, 3)
    end

    love.graphics.pop()
  end
end

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