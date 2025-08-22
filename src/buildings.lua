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
  elseif buildingType == 'market' then color = { 0.85, 0.5, 0.25, 1.0 }
  elseif buildingType == 'farm' then color = { 0.7, 0.8, 0.3, 1.0 }
  elseif buildingType == 'research' then color = { 0.5, 0.6, 0.9, 1.0 }
  elseif buildingType == 'flowerbed' then color = { 0.95, 0.65, 0.75, 1.0 }
  end
  local newB = {
    id = (state.game._nextBuildingId or 1),
    type = buildingType,
    tileX = tileX,
    tileY = tileY,
    color = color,
    anim = { appear = 0, t = 0, active = false },
    assigned = 0,
    currentResidents = 0,
    storage = { wood = 0, food = 0 },
    construction = {
      required = (def and def.buildRequired) or 10,
      progress = 0,
      complete = (buildingType == 'house' and false) or false,
      waitingForResources = false
    }
  }
  
  -- Initialize farm plots (surrounding tiles) and clear trees there
  if buildingType == 'farm' then
    newB.farm = { plots = {}, acc = 0 }
    for dy = -1, 1 do
      for dx = -1, 1 do
        if not (dx == 0 and dy == 0) then
          local nx, ny = tileX + dx, tileY + dy
          if nx >= 0 and ny >= 0 and nx < state.world.tilesX and ny < state.world.tilesY then
            trees.removeAt(state, nx, ny)
            table.insert(newB.farm.plots, { dx = dx, dy = dy })
          end
        end
      end
    end
  end

  table.insert(state.game.buildings, newB)
  state.game._nextBuildingId = (state.game._nextBuildingId or 1) + 1

  -- If placed while waiting for resources, push into build queue
  if newB.construction and newB.construction.waitingForResources then
    state.game.buildQueue = state.game.buildQueue or {}
    table.insert(state.game.buildQueue, { id = newB.id, priority = 0, paused = false })
  end

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
    elseif b.type == 'farm' then
      -- active if staffed and complete; actual production handled by workers
      local staffed = (b.assigned or 0) > 0
      b.anim.active = staffed and b.construction and b.construction.complete
    end

    -- Do not auto-pay; builders fetch and spend when they start the job
  end
  -- remove completed builds from queue
  if state.game.buildQueue and #state.game.buildQueue > 0 then
    local newQ = {}
    local byId = {}
    for _, bb in ipairs(state.game.buildings) do byId[bb.id] = bb end
    for _, q in ipairs(state.game.buildQueue) do
      local bb = byId[q.id]
      if bb and bb.construction and not bb.construction.complete then
        table.insert(newQ, q)
      end
    end
    state.game.buildQueue = newQ
  end
end

-- Cancel a planned/under-construction building
function buildings.cancel(state, b)
  if not b then return false end
  -- Refund policy: 100% if waitingForResources, else 50% if construction started and not complete
  local def = state.buildingDefs[b.type]
  local costWood = (def and def.cost and def.cost.wood) or 0
  local refund = 0
  if b.construction and b.construction.waitingForResources then
    refund = costWood -- nothing was paid yet; grant full refund
  elseif b.construction and not b.construction.complete then
    refund = math.floor(costWood * 0.5 + 0.5)
  end
  if refund > 0 then
    state.game.resources.wood = (state.game.resources.wood or 0) + refund
  end
  -- Roll back capacity added on placement for house/builder
  if b.type == 'house' then
    local cap = (state.buildingDefs.house.residents or 0)
    state.game.population.capacity = math.max(0, (state.game.population.capacity or 0) - cap)
  elseif b.type == 'builder' then
    local cap = (state.buildingDefs.builder.residents or 0)
    state.game.population.capacity = math.max(0, (state.game.population.capacity or 0) - cap)
  end
  -- Remove from build queue
  if state.game.buildQueue and #state.game.buildQueue > 0 then
    local newQ = {}
    for _, q in ipairs(state.game.buildQueue) do
      if q.id ~= b.id then table.insert(newQ, q) end
    end
    state.game.buildQueue = newQ
  end
  -- Remove from buildings list
  local idx
  for i, bb in ipairs(state.game.buildings) do if bb == b then idx = i; break end end
  if idx then table.remove(state.game.buildings, idx) end
  return true
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
  elseif b.type == 'farm' then
    local free = (state.game.population.total or 0) - (state.game.population.assigned or 0)
    local maxSlots = state.buildingDefs.farm.numWorkers or 0
    if free <= 0 or (b.assigned or 0) >= maxSlots then return false end
    b.assigned = (b.assigned or 0) + 1
    state.game.population.assigned = (state.game.population.assigned or 0) + 1
    workers.spawnAssignedWorker(state, b)
    return true
  elseif b.type == 'research' then
    local free = (state.game.population.total or 0) - (state.game.population.assigned or 0)
    local maxSlots = state.buildingDefs.research.numWorkers or 0
    if free <= 0 or (b.assigned or 0) >= maxSlots then return false end
    b.assigned = (b.assigned or 0) + 1
    state.game.population.assigned = (state.game.population.assigned or 0) + 1
    workers.spawnAssignedWorker(state, b)
    return true
  end
  return false
end

function buildings.unassignOne(state, b)
  if b.type ~= 'lumberyard' and b.type ~= 'builder' and b.type ~= 'farm' and b.type ~= 'research' then return false end
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
  -- clear tooltip each frame (will be set when hovering indicators)
  state.ui._noWorkTooltip = nil
  for _, b in ipairs(state.game.buildings) do
    local px = b.tileX * TILE_SIZE
    local py = b.tileY * TILE_SIZE
    local cx = px + TILE_SIZE / 2
    local cy = py + TILE_SIZE / 2

    -- skip shadow for decor like flowerbeds
    if b.type ~= 'flowerbed' then
      love.graphics.setColor(0, 0, 0, 0.18)
      love.graphics.ellipse('fill', cx, py + TILE_SIZE * 0.9, TILE_SIZE * 0.35, TILE_SIZE * 0.18)
    end

    local appear = (b.anim and b.anim.appear) or 1
    local t = (b.anim and b.anim.t) or 0
    local breath = 1 + 0.02 * math.sin(t * 3.0)
    local scale = (0.9 + 0.1 * appear) * breath

    -- flash decay
    if b._flashT and b._flashT > 0 then b._flashT = math.max(0, b._flashT - (state and state.time and 1/60 or 0.016)) end
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(scale, scale)

    -- skip square tile base for flowerbeds to blend with grass
    if b.type ~= 'flowerbed' then
      drawTileBase(TILE_SIZE, b.color)
    end

    -- Priority glow if this building is top of queue
    do
      local q = state.game.buildQueue or {}
      if #q > 0 and q[1] and q[1].id == b.id then
        local glowT = (b.anim and b.anim.t or 0)
        local alpha = 0.25 + 0.15 * (0.5 + 0.5 * math.sin(glowT * 3.5))
        love.graphics.setColor(1, 0.9, 0.3, alpha)
        love.graphics.rectangle('line', -TILE_SIZE/2 - 3, -TILE_SIZE/2 - 3, TILE_SIZE + 6, TILE_SIZE + 6, 8, 8)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end

    -- draw icon if available (except farm: draw procedural windmill + crops; flowerbed draws procedurally)
    if b.type ~= 'farm' and b.type ~= 'flowerbed' then
      local innerPad = 0
      drawBuildingIcon(b.type, TILE_SIZE, innerPad)
    end
    if b._flashT and b._flashT > 0 then
      love.graphics.setColor(1, 1, 0.6, 0.35 * (b._flashT / 0.5))
      love.graphics.rectangle('line', -TILE_SIZE/2 - 2, -TILE_SIZE/2 - 2, TILE_SIZE + 4, TILE_SIZE + 4, 8, 8)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Construction visuals
    if b.construction and not b.construction.complete then
      local p = (b.construction.progress or 0) / (b.construction.required or 1)
      -- rising scaffolding frame
      do
        local h = TILE_SIZE * (0.25 + 0.6 * p)
        love.graphics.setColor(0.35, 0.22, 0.12, 0.9)
        love.graphics.rectangle('fill', -TILE_SIZE/2 + 3, TILE_SIZE/2 - h, 4, h)
        love.graphics.rectangle('fill', TILE_SIZE/2 - 7, TILE_SIZE/2 - h, 4, h)
        for i=0,3 do
          local y = TILE_SIZE/2 - h + i * (h/3)
          love.graphics.rectangle('fill', -TILE_SIZE/2 + 3, y, TILE_SIZE - 14, 3)
        end
      end
      -- flickering hammer spark if a builder is assigned here
      if b._claimedBy then
        local t = (b.anim and b.anim.t or 0)
        local flicker = (math.sin(t * 30) > 0.85)
        if flicker then
          love.graphics.setColor(1, 0.9, 0.3, 0.9)
          love.graphics.circle('fill', 0, 0, 2)
        end
      end
      -- progress bar (styled)
      love.graphics.setColor(0, 0, 0, 0.45)
      love.graphics.rectangle('fill', -TILE_SIZE / 2, TILE_SIZE * 0.48, TILE_SIZE, 6, 3, 3)
      love.graphics.setColor(0.20, 0.78, 0.30, 1)
      love.graphics.rectangle('fill', -TILE_SIZE / 2, TILE_SIZE * 0.48, TILE_SIZE * p, 6, 3, 3)
      love.graphics.setColor(colors.outline)
      love.graphics.rectangle('line', -TILE_SIZE / 2, TILE_SIZE * 0.48, TILE_SIZE, 6, 3, 3)
      -- dust motes rising lightly
      if (b._dustT or 0) <= 0 then
        particles.spawnDustBurst(state.game.particles, cx, cy + TILE_SIZE * 0.25)
        b._dustT = 0.8 + math.random() * 0.6
      else
        b._dustT = b._dustT - (state and state.time and 1/60 or 0.016)
      end
    end

    -- Auto-assign one worker to research when it completes (if available)
    if b.type == 'research' and b.construction and b.construction.complete and not b._autoAssignedOnce then
      b._autoAssignedOnce = true
      local free = (state.game.population.total or 0) - (state.game.population.assigned or 0)
      if free > 0 then
        local ok = require('src.buildings').assignOne(state, b)
        if ok then
          state.ui.promptText = "A worker has been assigned to Research Center"
          state.ui.promptT = 0
          state.ui.promptDuration = 2
          state.ui.promptSticky = false
        end
      end
    end

    -- Fancy exclamation indicator when workers have nothing to do
    if b._noWorkReason then
      local t = (b.anim and b.anim.t or 0)
      local anchorX = TILE_SIZE * 0.35
      local anchorY = -TILE_SIZE * 0.38
      local bob = math.sin(t * 4.0) * 2
      local pulse = 1 + 0.06 * math.sin(t * 6.0)
      love.graphics.push()
      love.graphics.translate(anchorX, anchorY + bob)
      love.graphics.scale(pulse, pulse)
      -- soft halo rings
      for i = 1, 3 do
        local a = 0.18 - (i - 1) * 0.05
        if a > 0 then
          love.graphics.setColor(1, 0.85, 0.2, a)
          love.graphics.circle('line', 0, 0, 10 + i * 3)
        end
      end
      -- badge body
      love.graphics.setColor(1, 0.9, 0.25, 1)
      love.graphics.circle('fill', 0, 0, 9)
      -- outline
      love.graphics.setColor(0.35, 0.2, 0, 0.9)
      love.graphics.setLineWidth(2)
      love.graphics.circle('line', 0, 0, 9)
      -- exclamation glyph
      love.graphics.setLineWidth(3)
      love.graphics.line(0, -5, 0, 1)
      love.graphics.setLineWidth(1)
      love.graphics.circle('fill', 0, 4, 2.4)
      -- tether line to building top
      love.graphics.setColor(0, 0, 0, 0.2)
      love.graphics.setLineWidth(1)
      love.graphics.line(0, 9, -anchorX * 0.2, TILE_SIZE * 0.18)
      love.graphics.pop()
      -- hover detection for tooltip (mouse in world space vs indicator world position)
      do
        local mx, my = love.mouse.getPosition()
        local worldX = state.camera.x + mx / (state.camera.scale or 1)
        local worldY = state.camera.y + my / (state.camera.scale or 1)
        local indWorldX = cx + anchorX * scale
        local indWorldY = cy + (anchorY + bob) * scale
        local dx, dy = worldX - indWorldX, worldY - indWorldY
        local r = 12 * scale
        if dx * dx + dy * dy <= r * r then
          state.ui._noWorkTooltip = { text = b._noWorkReason, sx = mx + 14, sy = my + 16 }
        end
      end
    end

    -- Farm: procedural windmill + crops
    if b.type == 'farm' then
      local t = (b.anim and b.anim.t) or 0
      -- ground patch only on the center tile
      love.graphics.setColor(0.30, 0.55, 0.25, 1)
      love.graphics.rectangle('fill', -TILE_SIZE/2 + 4, -TILE_SIZE/2 + 4, TILE_SIZE - 8, TILE_SIZE - 8, 6, 6)
      love.graphics.setColor(0.22, 0.45, 0.18, 1)
      love.graphics.rectangle('line', -TILE_SIZE/2 + 4, -TILE_SIZE/2 + 4, TILE_SIZE - 8, TILE_SIZE - 8, 6, 6)
      -- windmill tower
      love.graphics.setColor(0.55, 0.42, 0.25, 1)
      love.graphics.rectangle('fill', -3, -TILE_SIZE*0.25, 6, TILE_SIZE*0.35, 2, 2)
      love.graphics.setColor(0.35, 0.22, 0.12, 1)
      love.graphics.rectangle('line', -3, -TILE_SIZE*0.25, 6, TILE_SIZE*0.35, 2, 2)
      -- hub
      love.graphics.setColor(0.85, 0.75, 0.5, 1)
      love.graphics.circle('fill', 0, -TILE_SIZE*0.25, 3)
      love.graphics.setColor(0.35, 0.22, 0.12, 1)
      love.graphics.circle('line', 0, -TILE_SIZE*0.25, 3)
      -- blades (rotate)
      local rot = t * 2.5
      local function blade(angle)
        local a = angle + rot
        local bx = math.cos(a)
        local by = math.sin(a)
        love.graphics.push()
        love.graphics.translate(0, -TILE_SIZE*0.25)
        love.graphics.rotate(a)
        love.graphics.setColor(0.90, 0.88, 0.78, 1)
        love.graphics.rectangle('fill', 0, -2, TILE_SIZE*0.22, 4, 2, 2)
        love.graphics.setColor(0.55, 0.48, 0.35, 1)
        love.graphics.rectangle('line', 0, -2, TILE_SIZE*0.22, 4, 2, 2)
        love.graphics.pop()
      end
      blade(0)
      blade(math.pi * 0.5)
      blade(math.pi)
      blade(math.pi * 1.5)
      -- crops filling the neighboring tiles around the center (no extra green patches)
      local farmExpanded = state.game and state.game.research and state.game.research.farmExpansionUnlocked
      local minG, maxG = -1, 1
      if farmExpanded then minG, maxG = -2, 2 end
      for gx = minG, maxG do
        for gy = -1, 1 do
          if not (gx == 0 and gy == 0) then
            local baseX = gx * TILE_SIZE
            local baseY = gy * TILE_SIZE
            local sway = math.sin(t * 3.0 + (gx * 3 + gy)) * 2.0
            love.graphics.setColor(0.95, 0.82, 0.35, 1)
            -- three small crop clumps per tile, lightly varied
            love.graphics.rectangle('fill', baseX - TILE_SIZE*0.25, baseY - 6 - sway, 6, 12, 2, 2)
            love.graphics.rectangle('fill', baseX - 2,              baseY - 5 - sway * 0.6, 5, 10, 2, 2)
            love.graphics.rectangle('fill', baseX + TILE_SIZE*0.25, baseY - 6 - sway * 0.4, 6, 12, 2, 2)
          end
        end
      end
    elseif b.type == 'research' then
      -- simple procedural research center: small pavilion with scrolls
      love.graphics.setColor(0.85, 0.82, 0.70, 1)
      love.graphics.rectangle('fill', -TILE_SIZE/2 + 6, -TILE_SIZE/2 + 12, TILE_SIZE - 12, TILE_SIZE - 18, 6, 6)
      love.graphics.setColor(0.35, 0.22, 0.12, 1)
      love.graphics.rectangle('line', -TILE_SIZE/2 + 6, -TILE_SIZE/2 + 12, TILE_SIZE - 12, TILE_SIZE - 18, 6, 6)
      -- roof
      love.graphics.setColor(0.55, 0.2, 0.2, 1)
      love.graphics.polygon('fill', -TILE_SIZE/2 + 2, -TILE_SIZE/2 + 12, 0, -TILE_SIZE/2 + 2, TILE_SIZE/2 - 2, -TILE_SIZE/2 + 12)
      love.graphics.setColor(0.35, 0.15, 0.12, 1)
      love.graphics.polygon('line', -TILE_SIZE/2 + 2, -TILE_SIZE/2 + 12, 0, -TILE_SIZE/2 + 2, TILE_SIZE/2 - 2, -TILE_SIZE/2 + 12)
      -- scroll on table
      love.graphics.setColor(0.95, 0.9, 0.75, 1)
      love.graphics.rectangle('fill', -12, 4, 24, 8, 3, 3)
      love.graphics.setColor(0.7, 0.6, 0.45, 1)
      love.graphics.rectangle('line', -12, 4, 24, 8, 3, 3)
    elseif b.type == 'flowerbed' then
      -- procedural flower bed: soil patch + scattered flowers
      love.graphics.setColor(0.35, 0.22, 0.12, 1)
      love.graphics.rectangle('fill', -TILE_SIZE/2 + 6, -TILE_SIZE/2 + 6, TILE_SIZE - 12, TILE_SIZE - 12, 6, 6)
      love.graphics.setColor(0.20, 0.50, 0.22, 1)
      love.graphics.rectangle('line', -TILE_SIZE/2 + 6, -TILE_SIZE/2 + 6, TILE_SIZE - 12, TILE_SIZE - 12, 6, 6)
      -- scatter flowers deterministically per building id
      local seed = (b.id or 1) * 9871
      local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed / 2147483648)
      end
      local colorsList = {
        {0.95, 0.65, 0.75, 1}, -- pink
        {0.95, 0.85, 0.35, 1}, -- yellow
        {0.75, 0.85, 0.95, 1}, -- light blue
        {0.90, 0.50, 0.40, 1}  -- coral
      }
      for i=1,10 do
        local fx = -TILE_SIZE/2 + 10 + rnd() * (TILE_SIZE - 20)
        local fy = -TILE_SIZE/2 + 10 + rnd() * (TILE_SIZE - 20)
        local c = colorsList[1 + math.floor(rnd() * #colorsList)]
        love.graphics.setColor(c)
        love.graphics.circle('fill', fx, fy, 2)
        love.graphics.setColor(0.18, 0.11, 0.06, 0.8)
        love.graphics.circle('line', fx, fy, 2)
      end
    end

    -- Market accents removed by request

    -- Floating selection label above the selected building (helps clicking on map)
    if state.ui.selectedBuilding == b then
      local label = string.format('%s  (%d,%d)', b.type, b.tileX, b.tileY)
      local fw = love.graphics.getFont():getWidth(label)
      local pad = 6
      local bw = fw + pad * 2
      local bh = 18
      local ox = 0
      local oy = -TILE_SIZE * 0.72
      love.graphics.setColor(0.35, 0.22, 0.12, 0.9)
      love.graphics.rectangle('fill', ox - bw/2 - 2, oy - bh/2 + 2, bw + 4, bh + 4, 6, 6)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', ox - bw/2, oy - bh/2, bw, bh, 6, 6)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', ox - bw/2, oy - bh/2, bw, bh, 6, 6)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(label, ox - bw/2 + pad, oy - bh/2 + 2)
    end

    love.graphics.pop()
  end
end

function buildings.drawSelectedRadius(state)
  local TILE_SIZE = constants.TILE_SIZE
  local b = state.ui.selectedBuilding
  if not b then return end
  local def
  local radiusTiles
  if b.type == 'lumberyard' then
    def = state.buildingDefs.lumberyard
    radiusTiles = def.radiusTiles
  elseif b.type == 'market' then
    def = state.buildingDefs.market
    radiusTiles = def.radiusTiles
  elseif b.type == 'flowerbed' then
    def = state.buildingDefs.flowerbed
    radiusTiles = def and def.radiusTiles
  else
    return
  end
  local radiusPx = (radiusTiles or 0) * TILE_SIZE
  if radiusPx <= 0 then return end
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