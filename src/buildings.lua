-- buildings.lua
-- Placement rules, building rendering and radii drawing

local constants = require('src.constants')
local trees = require('src.trees')
local utils = require('src.utils')
local particles = require('src.particles')
local colors = constants.colors
local workers = require('src.workers')

-- Image cache for building icons
local imageCache = {}
local function getImageMeta(typ)
  if imageCache[typ] ~= nil then return imageCache[typ] end
  local path = string.format('assets/%s.png', typ)
  if not love.filesystem.getInfo(path) then
    imageCache[typ] = false
    return imageCache[typ]
  end
  local okData, data = pcall(love.image.newImageData, path)
  local okImg, img = pcall(love.graphics.newImage, path)
  if not okData or not okImg then
    imageCache[typ] = false
    return imageCache[typ]
  end
  local w, h = data:getWidth(), data:getHeight()
  local minX, minY = w - 1, h - 1
  local maxX, maxY = 0, 0
  local found = false
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = data:getPixel(x, y)
      if a and a > 0.02 then
        found = true
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
      end
    end
  end
  local ox, oy
  if found then
    ox = (minX + maxX) / 2
    oy = (minY + maxY) / 2
  else
    ox = w / 2
    oy = h / 2
  end
  imageCache[typ] = { img = img, iw = w, ih = h, ox = ox, oy = oy }
  return imageCache[typ]
end

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
  state.game.resources._spentAny = true
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
    anim = { appear = 0, t = 0, active = false },
    assigned = 0,
    currentResidents = 0,
    storage = { wood = 0 },
    construction = {
      required = (def and def.buildRequired) or 10,
      progress = 0,
      complete = (buildingType == 'house' and false) or false
    }
  }
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
    b.anim = b.anim or { appear = 1, t = 0, active = false }
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

function buildings.demolish(state, b)
  if not b then return false end
  -- Remove from list
  local idx
  for i, bb in ipairs(state.game.buildings) do if bb == b then idx = i; break end end
  if not idx then return false end

  -- Refund 50% of wood cost
  local def = state.buildingDefs[b.type]
  local refund = 0
  if def and def.cost and def.cost.wood then
    refund = math.floor((def.cost.wood * 0.5) + 0.5)
  end
  if refund > 0 then
    -- Prefer putting refund into base resources
    state.game.resources.wood = (state.game.resources.wood or 0) + refund
  end

  -- Adjust population if house or builder (capacity)
  if b.type == 'house' then
    local cap = (state.buildingDefs.house.residents or 0)
    state.game.population.capacity = math.max(0, (state.game.population.capacity or 0) - cap)
    state.game.population.total = math.max(0, (state.game.population.total or 0) - cap)
  elseif b.type == 'builder' then
    local cap = (state.buildingDefs.builder.residents or 0)
    state.game.population.capacity = math.max(0, (state.game.population.capacity or 0) - cap)
    state.game.population.total = math.max(0, (state.game.population.total or 0) - cap)
  end

  -- Free assigned workers count
  if b.assigned and b.assigned > 0 then
    state.game.population.assigned = math.max(0, (state.game.population.assigned or 0) - b.assigned)
  end

  table.remove(state.game.buildings, idx)
  return true
end

local function drawTileBase(TILE_SIZE, color)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", -TILE_SIZE / 2, -TILE_SIZE / 2, TILE_SIZE, TILE_SIZE, 6, 6)
  love.graphics.setColor(colors.outline)
  love.graphics.rectangle("line", -TILE_SIZE / 2, -TILE_SIZE / 2, TILE_SIZE, TILE_SIZE, 6, 6)
end

local function drawBuildingIcon(typ, TILE_SIZE, innerPad)
  local meta = getImageMeta(typ)
  if not meta or meta == false then return end
  love.graphics.setColor(1, 1, 1, 1)
  local iw, ih = meta.iw, meta.ih
  local maxW = TILE_SIZE - innerPad * 2
  local maxH = TILE_SIZE - innerPad * 2
  -- Scale large and center using visual center (ignores transparent margins)
  local s = math.min(maxW / iw, maxH / ih) * 1.12
  love.graphics.draw(meta.img, 0, 0, 0, s, s, meta.ox, meta.oy)
end

-- Public: draw an icon at screen-space position (x,y) centered, with a square size
function buildings.drawIcon(typ, x, y, size, pad)
  local meta = getImageMeta(typ)
  if not meta or meta == false then return end
  local iw, ih = meta.iw, meta.ih
  local inner = (size or 32) - (pad or 0) * 2
  local s = math.min(inner / iw, inner / ih) * 1.06
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(meta.img, x, y, 0, s, s, meta.ox, meta.oy)
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

    drawTileBase(TILE_SIZE, b.color)

    -- draw icon if available
    local innerPad = 0
    drawBuildingIcon(b.type, TILE_SIZE, innerPad)

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