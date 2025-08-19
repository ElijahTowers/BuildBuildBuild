-- main.lua
-- Entry point: orchestrates modules and game loop

-- Module imports
local C = require('src.constants')
local utils = require('src.utils')
local state = require('src.state')
local trees = require('src.trees')
local grid = require('src.grid')
local particles = require('src.particles')
local buildings = require('src.buildings')
local workers = require('src.workers')
local ui = require('src.ui')
local save = require('src.save')
local roads = require('src.roads')
local missions = require('src.missions')

-- Shorthand
local TILE_SIZE = C.TILE_SIZE
local colors = C.colors

-- Converts mouse screen position to world tile coordinates
local function getMouseTile()
  local mx, my = love.mouse.getX(), love.mouse.getY()
  local worldX = state.camera.x + mx / state.camera.scale
  local worldY = state.camera.y + my / state.camera.scale
  local tileX = math.floor(worldX / TILE_SIZE)
  local tileY = math.floor(worldY / TILE_SIZE)
  return tileX, tileY
end

-- Convert explicit screen coords to tile (use for click handling to avoid drift)
local function screenToTile(sx, sy)
  local worldX = state.camera.x + sx / state.camera.scale
  local worldY = state.camera.y + sy / state.camera.scale
  return math.floor(worldX / TILE_SIZE), math.floor(worldY / TILE_SIZE)
end

-- Returns true if mouse is over any UI panel (build button or build menu)
local function isOverUI(mx, my)
  if ui.isOverBuildButton(mx, my) then return true end
  local m = ui.buildMenu
  if state.ui.isBuildMenuOpen then
    if utils.isPointInRect(mx, my, m.x, m.y, m.width, m.height) then
      return true
    end
  end
  return false
end

-- Count warehouses in the world
local function countWarehouses()
  local c = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' then c = c + 1 end
  end
  return c
end

-- Compute total wood across base and warehouses
local function computeTotalWood()
  local total = state.game.resources.wood or 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      total = total + b.storage.wood
    end
  end
  return total
end

-- Compute total wood capacity (base + per-warehouse)
local function computeWoodCapacity()
  return 50 + 100 * countWarehouses()
end

-- Draw a placement preview at mouse tile, including lumberyard radius
local function drawPlacementPreview()
  if state.ui.isPaused then return end
  if not state.ui.isPlacingBuilding or not state.ui.selectedBuildingType then return end

  local tileX, tileY = getMouseTile()
  local px = tileX * TILE_SIZE
  local py = tileY * TILE_SIZE

  local isValid = buildings.canPlaceAt(state, tileX, tileY)
    and not isOverUI(love.mouse.getX(), love.mouse.getY())

  -- Show lumberyard/market radius while previewing
  if state.ui.selectedBuildingType == 'lumberyard' or state.ui.selectedBuildingType == 'market' then
    local def = state.buildingDefs[state.ui.selectedBuildingType]
    local radiusPx = (def.radiusTiles or 0) * TILE_SIZE
    local cx = px + TILE_SIZE / 2
    local cy = py + TILE_SIZE / 2
    love.graphics.setColor(colors.radius)
    love.graphics.circle('fill', cx, cy, radiusPx)
    love.graphics.setColor(colors.radiusOutline)
    love.graphics.circle('line', cx, cy, radiusPx)
  end

  -- Show farm surrounding plots while previewing
  if state.ui.selectedBuildingType == 'farm' then
    for dy = -1, 1 do
      for dx = -1, 1 do
        if not (dx == 0 and dy == 0) then
          local nx = px + dx * TILE_SIZE
          local ny = py + dy * TILE_SIZE
          love.graphics.setColor(0.35, 0.6, 0.2, 0.35)
          love.graphics.rectangle('fill', nx, ny, TILE_SIZE, TILE_SIZE, 4, 4)
          love.graphics.setColor(colors.outline[1], colors.outline[2], colors.outline[3], 0.25)
          love.graphics.rectangle('line', nx, ny, TILE_SIZE, TILE_SIZE, 4, 4)
        end
      end
    end
  end

  if not isValid then
    love.graphics.setColor(colors.invalid)
  else
    local t = state.ui.selectedBuildingType
    if t == 'house' then
      love.graphics.setColor(0.9, 0.6, 0.2, colors.preview[4])
    elseif t == 'lumberyard' then
      love.graphics.setColor(0.3, 0.7, 0.3, colors.preview[4])
    else
      love.graphics.setColor(colors.preview)
    end
  end

  love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE, 4, 4)

  -- pulsing outline
  local pulse = 0.5 + 0.5 * math.sin(state.ui.previewT * 6)
  love.graphics.setColor(colors.outline[1], colors.outline[2], colors.outline[3], 0.2 + 0.4 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle('line', px, py, TILE_SIZE, TILE_SIZE, 4, 4)
  love.graphics.setLineWidth(1)
end

-- Pause menu click handling
local function handlePauseMenuClick(x, y)
  if not state.ui.isPaused then return false end
  for _, opt in ipairs(ui.pauseMenu.options) do
    local b = opt._bounds
    if b and utils.isPointInRect(x, y, b.x, b.y, b.w, b.h) then
      if opt.key == 'resume' then
        state.ui.isPaused = false
      elseif opt.key == 'save' then
        state.ui._saveLoadMode = 'save'
      elseif opt.key == 'load' then
        state.ui._saveLoadMode = 'load'
      elseif opt.key == 'restart' then
        state.restart()
        trees.generate(state)
        missions.init(state)
      elseif opt.key == 'quit' then
        love.event.quit()
      end
      return true
    end
  end
  return true
end

function love.load()
  love.window.setTitle('City Builder - Prototype')
  love.graphics.setBackgroundColor(colors.background)

  math.randomseed(os.time())
  state.resetWorldTilesFromScreen()
  ui.computeBuildMenuHeight()
    trees.generate(state)
  missions.init(state)
 
  -- Start at beginning of the day (around sunrise ~06:00)
  state.time.t = state.time.dayLength * 0.25
  state.time.normalized = state.time.t / state.time.dayLength

  -- Start with free builder placement preview
  state.ui.isPlacingBuilding = true
  state.ui.selectedBuildingType = 'builder'
  state.ui._isFreeInitialBuilder = true
  -- Pause time until initial builder is placed
  state.ui._pauseTimeForInitial = true
  -- Prompt the player to place the builders workplace
  state.ui.promptText = "Place your Builders Workplace for free. Left-click a tile to place."
  state.ui.promptT = 0
  state.ui.promptDuration = 9999
end

function love.update(dt)
  if state.ui.isPaused or state.ui.isBuildMenuOpen or state.ui.isVillagersPanelOpen or state.ui.isBuildQueueOpen or state.ui.isFoodPanelOpen then return end
  local isInitial = state.ui._pauseTimeForInitial

  -- Auto speed by day/night
  local isDay = (state.time.normalized >= 0.25 and state.time.normalized < 0.75)
  if state.time.lastIsDay == nil then
    state.time.lastIsDay = isDay
  else
    if isDay ~= state.time.lastIsDay then
      if isDay then
        -- restore pre-night speed
        state.time.speed = state.time.preNightSpeed or 1
        -- new day: reset synchronized mealtime flag
        state.time.mealConsumedToday = false
        state.time.mealtimeActive = false
        state.game.starving = false
        -- reset per-villager meal flags
        if state.game and state.game.villagers then
          for _, v in ipairs(state.game.villagers) do v._ateToday = false end
        end
        if state.game and state.game.buildings then
          for _, b in ipairs(state.game.buildings) do
            if b.workers then
              for _, w in ipairs(b.workers) do w._ateToday = false end
            end
          end
        end
      else
        -- entering night: remember current speed then switch to 8x
        state.time.preNightSpeed = state.time.speed or 1
        state.time.speed = 8
        state.time.mealtimeActive = false
      end
      state.time.lastIsDay = isDay
    end
  end

  -- Clear stale food-shortage prompt if conditions are now OK (e.g., after deliveries)
  do
    local popNow = state.game.population.total or 0
    local marketsFoodNow, marketsCount = 0, 0
    for _, b in ipairs(state.game.buildings) do
      if b.type == 'market' then
        marketsCount = marketsCount + 1
        if b.storage and b.storage.food then marketsFoodNow = marketsFoodNow + b.storage.food end
      end
    end
    if marketsCount > 0 and marketsFoodNow >= popNow then
      if state.ui.prompts then
        local newList = {}
        for _, p in ipairs(state.ui.prompts) do
          if p.tag ~= 'market_food' then table.insert(newList, p) end
        end
        state.ui.prompts = newList
      end
      state.game.starving = false
    end
  end

  -- Time of day (apply time speed)
  local sdt = dt * (state.time.speed or 1)
  if not isInitial then
    state.time.t = (state.time.t + sdt) % state.time.dayLength
    state.time.normalized = state.time.t / state.time.dayLength
  end

  -- Synchronized daily mealtime: all villagers eat just before nightfall
  do
    local pop = state.game.population.total or 0
    if pop > 0 and not isInitial then
      -- Trigger mealtime during late day window before night (day ends at tnorm 0.75)
      local tnorm = state.time.normalized
      -- start directing villagers to market slightly earlier
      if (not state.time.mealtimeActive) and (tnorm >= 0.70 and tnorm < 0.75) then
        state.time.mealtimeActive = true
      end
      if (not state.time.mealConsumedToday) and (tnorm >= 0.73 and tnorm < 0.75) then
        local remaining = pop
        local consumed = 0
        local markets = {}
        for _, b in ipairs(state.game.buildings) do
          if b.type == 'market' then table.insert(markets, b) end
        end
        if #markets > 0 then
          for _, m in ipairs(markets) do
            if remaining <= 0 then break end
            local stock = (m.storage and m.storage.food) or 0
            if stock > 0 then
              local take = math.min(remaining, stock)
              m.storage.food = stock - take
              remaining = remaining - take
              consumed = consumed + take
            end
          end
        end
        local mealOk = (consumed >= pop)
        state.time.mealConsumedToday = true
        state.time.mealtimeActive = true
        state.time.lastMealOk = mealOk
        state.game.starving = not mealOk

        -- Prompt player if villagers could not get food at the market
        state.ui.prompts = state.ui.prompts or {}
        local function upsertPrompt(tag, text)
          local found = false
          for _, p in ipairs(state.ui.prompts) do
            if p.tag == tag then
              p.text = text; p.duration = 999999; p.useRealTime = true; found = true; break
            end
          end
          if not found then table.insert(state.ui.prompts, { text = text, t = 0, duration = 999999, useRealTime = true, tag = tag }) end
        end
        local function removePrompt(tag)
          local newList = {}
          for _, p in ipairs(state.ui.prompts) do if p.tag ~= tag then table.insert(newList, p) end end
          state.ui.prompts = newList
        end
        if not mealOk then
          if #markets == 0 then
            upsertPrompt('market_food', 'Villagers could not eat: build a Market and stock it with food before dusk.')
          else
            upsertPrompt('market_food', 'Villagers could not eat: not enough food in Markets. Stock them before dusk.')
          end
        else
          removePrompt('market_food')
        end
        -- Safety: immediately clear the prompt if at any time after mealtime stock becomes sufficient
        if state.ui.prompts and state.time.mealConsumedToday then
          local totalMarketFood = 0
          for _, m in ipairs(state.game.buildings) do
            if m.type == 'market' and m.storage and m.storage.food then totalMarketFood = totalMarketFood + m.storage.food end
          end
          if totalMarketFood >= (state.game.population.total or 0) then
            removePrompt('market_food')
            state.game.starving = false
          end
        end
      end
    end
  end

  -- Passive production placeholder (none currently for lumberyard)
  state.game.productionRates.wood = 0

  -- Global prompt for full storage (base or warehouses)
  do
    local totalWood = computeTotalWood()
    local cap = computeWoodCapacity()
    local warehouses = countWarehouses()

    if totalWood >= cap and not state.ui._pauseTimeForInitial and state.game.resources._spentAny then
      local text
      if warehouses == 0 then
        text = "Storage is full (50). Build a Warehouse to increase capacity (+100)."
      else
        text = string.format("Storage is full (%d). Build another Warehouse to increase capacity (+100).", cap)
      end
      state.ui.prompts = state.ui.prompts or {}
      local found = false
      for _, p in ipairs(state.ui.prompts) do
        if p.tag == 'capacity' then
          p.text = text
          p.duration = 999999
          p.useRealTime = true
          found = true
          break
        end
      end
      if not found then
        table.insert(state.ui.prompts, { text = text, t = 0, duration = 999999, useRealTime = true, tag = 'capacity' })
      end
      state.ui._lastCapacityPrompted = cap
    else
      -- Not full anymore or still in initial placement; remove any capacity prompt
      if state.ui.prompts then
        local newList = {}
        for _, p in ipairs(state.ui.prompts) do
          if p.tag ~= 'capacity' then table.insert(newList, p) end
        end
        state.ui.prompts = newList
      end
      if state.ui._lastCapacityPrompted then
        state.ui.promptText = nil
        state.ui.promptDuration = 0
        state.ui.promptSticky = false
        state.ui._lastCapacityPrompted = nil
      end
    end
  end

  -- Systems
  missions.update(state, dt)
  if not isInitial then
    workers.update(state, sdt)
  end
  buildings.update(state, sdt)
  particles.update(state.game.particles, sdt)
  trees.updateShake(state, sdt)
  roads.update(state, sdt)

  -- Preview timer for pulsing outline
  state.ui.previewT = state.ui.previewT + sdt
  -- Stacked prompts update
  do
    state.ui.prompts = state.ui.prompts or {}
    local newList = {}
    local seenTags = {}
    for _, p in ipairs(state.ui.prompts) do
      -- filter out initial placement prompt once initial phase ended
      if not (not state.ui._pauseTimeForInitial and p.text and p.text:find('Place your Builders Workplace')) then
        local inc = (p.useRealTime and dt) or sdt
        p.t = (p.t or 0) + inc
        -- de-dupe by tag: keep first only
        local tag = p.tag
        if tag then
          if not seenTags[tag] and (not p.duration or p.t < p.duration) then
            table.insert(newList, p)
            seenTags[tag] = true
          end
        else
          if not p.duration or p.t < p.duration then
            table.insert(newList, p)
          end
        end
      end
    end
    state.ui.prompts = newList
  end
  -- Back-compat single prompt funnels into stacked list
  if state.ui.promptText and state.ui.promptDuration and state.ui.promptDuration > 0 then
    table.insert(state.ui.prompts, { text = state.ui.promptText, t = 0, duration = state.ui.promptDuration, useRealTime = state.ui._promptUseRealTime })
    state.ui.promptText = nil; state.ui.promptDuration = 0; state.ui._promptUseRealTime = nil
  end

  -- Mouse edge panning (not speed-scaled)
  local mx, my = love.mouse.getPosition()
  local screenW, screenH = love.graphics.getDimensions()
  local margin = 24
  local dx, dy = 0, 0
  if mx <= margin then dx = -1 end
  if mx >= screenW - margin then dx = 1 end
  if my <= margin then dy = -1 end
  if my >= screenH - margin then dy = 1 end

  state.camera.x = state.camera.x + dx * state.camera.panSpeed * dt / state.camera.scale
  state.camera.y = state.camera.y + dy * state.camera.panSpeed * dt / state.camera.scale

  local maxCamX = math.max(0, state.world.tilesX * TILE_SIZE - screenW / state.camera.scale)
  local maxCamY = math.max(0, state.world.tilesY * TILE_SIZE - screenH / state.camera.scale)
  state.camera.x = utils.clamp(state.camera.x, 0, maxCamX)
  state.camera.y = utils.clamp(state.camera.y, 0, maxCamY)
end

local function getAmbientColor()
  -- Map normalized time [0..1) to ambient brightness/color
  -- Dawn 0.2, Day 0.8, Dusk 0.2, Night 0.05
  local t = state.time.normalized
  local function lerp(a, b, u) return a + (b - a) * u end
  local brightness
  if t < 0.25 then
    -- Night -> Dawn
    brightness = lerp(0.05, 0.8, t / 0.25)
  elseif t < 0.5 then
    -- Day
    brightness = 0.8
  elseif t < 0.75 then
    -- Dusk
    brightness = lerp(0.8, 0.2, (t - 0.5) / 0.25)
  else
    -- Night
    brightness = 0.05
  end
  -- Slight warm tint at sunrise/sunset
  local warm = math.max(0, 0.5 - math.abs(t - 0.5)) * 0.2
  local r = brightness + warm * 0.2
  local g = brightness + warm * 0.1
  local b = brightness
  return r, g, b
end

local function drawDayNightOverlay()
  local screenW, screenH = love.graphics.getDimensions()
  local r, g, b = getAmbientColor()
  -- Darken based on inverse brightness
  local darkness = 1 - math.min(1, (r + g + b) / 3)
  love.graphics.setColor(0, 0, 0, 0.5 * darkness)
  love.graphics.rectangle('fill', 0, 0, screenW, screenH)
end

function love.draw()
  -- World space draw
  love.graphics.push()
  love.graphics.scale(state.camera.scale, state.camera.scale)
  love.graphics.translate(-state.camera.x, -state.camera.y)

  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    grid.draw(state)
  end
  buildings.drawSelectedRadius(state)
  trees.draw(state)
  roads.draw(state)
  buildings.drawAll(state)
  workers.draw(state)

  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    local screenW, screenH = love.graphics.getDimensions()
    local visibleW = screenW / (state.camera.scale or 1)
    local visibleH = screenH / (state.camera.scale or 1)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle('fill', state.camera.x, state.camera.y, visibleW, visibleH)
  end

  if state.ui.isPlacingRoad and state.ui.roadStartTile then
    local sx, sy = state.ui.roadStartTile.x, state.ui.roadStartTile.y
    local ex, ey = getMouseTile()
    local path = roads.computePath(state, sx, sy, ex, ey)
    -- Include the start tile so preview shows the first placed cell too
    if roads.canPlaceAt(state, sx, sy) and not roads.hasRoad(state, sx, sy) then
      table.insert(path, 1, { x = sx, y = sy })
    end
    roads.drawPreview(state, path)
  elseif state.ui.isPlacingRoad and not state.ui.roadStartTile then
    -- show single-tile hover preview to indicate road mode
    local tx, ty = getMouseTile()
    local TILE = TILE_SIZE
    if roads.canPlaceAt(state, tx, ty) and not roads.hasRoad(state, tx, ty) then
      love.graphics.setColor(colors.preview)
    else
      love.graphics.setColor(colors.invalid)
    end
    love.graphics.rectangle('fill', tx * TILE, ty * TILE, TILE, TILE, 4, 4)
    love.graphics.setColor(colors.outline)
    love.graphics.rectangle('line', tx * TILE, ty * TILE, TILE, TILE, 4, 4)
  end

  drawPlacementPreview()
  particles.draw(state.game.particles)

  love.graphics.pop()

  -- Day-night overlay over world and under UI
  drawDayNightOverlay()

  -- UI draw
  ui.drawTopButtons(state)
  ui.drawBuildMenu(state, state.buildingDefs)
  ui.drawHUD(state)
  ui.drawFoodPanel(state)
  ui.drawBuildQueue(state)
  ui.drawMiniMap(state)
  ui.drawMissionPanel(state)
  ui.drawPrompt(state)

  local sel = state.ui.selectedBuilding
  if sel then
    ui.drawSelectedPanel(state)
  end

  -- Tooltip for no-work indicator
  do
    local tip = state.ui._noWorkTooltip
    if tip and tip.text then
      local tw = love.graphics.getFont():getWidth(tip.text) + 12
      local th = 22
      love.graphics.setColor(0, 0, 0, 0.75)
      love.graphics.rectangle('fill', tip.sx, tip.sy, tw, th, 6, 6)
      love.graphics.setColor(colors.uiPanelOutline)
      love.graphics.rectangle('line', tip.sx, tip.sy, tw, th, 6, 6)
      love.graphics.setColor(colors.text)
      love.graphics.print(tip.text, tip.sx + 6, tip.sy + 4)
    end
  end

  if not state.ui.isPaused and not state.ui.isBuildMenuOpen then
    love.graphics.setColor(colors.text)
    local hintY = love.graphics.getHeight() - 24
    love.graphics.print("Click 'Build' -> choose 'House' or 'Lumberyard' -> place on the map. Move mouse to screen edges to pan. Right click to cancel placement.", 16, hintY)
  end

  -- Do not show pause menu if Food Panel is open (even if paused)
  if not state.ui.isFoodPanelOpen then
    ui.drawPauseMenu(state)
  end
end

local function hitTestBuildingAt(state, tileX, tileY)
  for _, b in ipairs(state.game.buildings) do
    if b.tileX == tileX and b.tileY == tileY then
      return b
    end
  end
  return nil
end

function love.mousepressed(x, y, button)
  -- During initial free placement, block all interactions except left-click placement
  if state.ui._isFreeInitialBuilder then
    if button ~= 1 then return end
    -- allow minimap navigation to find a placement spot
    local mm = state.ui._miniMap
    if mm and x >= mm.x and x <= mm.x + mm.w and y >= mm.y and y <= mm.y + mm.h then
      local TILE = C.TILE_SIZE
      local screenW, screenH = love.graphics.getDimensions()
      local worldX = (x - mm.x) / mm.scale * TILE
      local worldY = (y - mm.y) / mm.scale * TILE
      state.camera.x = utils.clamp(worldX - (screenW / state.camera.scale) / 2, 0, state.world.tilesX * TILE - (screenW / state.camera.scale))
      state.camera.y = utils.clamp(worldY - (screenH / state.camera.scale) / 2, 0, state.world.tilesY * TILE - (screenH / state.camera.scale))
      return
    end
    -- ensure we're placing builder
    state.ui.isPlacingBuilding = true
    state.ui.selectedBuildingType = 'builder'
    local tileX, tileY = screenToTile(x, y)
    if buildings.canPlaceAt(state, tileX, tileY) then
      local newB = buildings.place(state, 'builder', tileX, tileY)
      -- complete instantly and start day with prompt
      newB.construction.progress = newB.construction.required
      newB.construction.complete = true
      local res = state.buildingDefs.builder.residents or 0
      state.game.population.total = (state.game.population.total or 0) + res
      -- auto-assign 2 workers if available
      local toAssign = math.min(2, state.buildingDefs.builder.numWorkers or 0)
      for i = 1, toAssign do
        require('src.buildings').assignOne(state, newB)
      end
      state.ui._isFreeInitialBuilder = nil
      state.ui._pauseTimeForInitial = nil
      state.ui.promptText = "Your Builders Workplace is ready. The first day begins!"
      state.ui.promptT = 0
      state.ui.promptDuration = 5
      state.time.t = state.time.dayLength * 0.25
      state.time.normalized = state.time.t / state.time.dayLength
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
    end
    return
  end

  if state.ui.isPaused and not state.ui.isBuildMenuOpen then
    if button == 1 then
      -- Handle save/load slot selection overlay if active
      if state.ui._saveLoadMode and state.ui._saveLoadButtons then
        for _, b in ipairs(state.ui._saveLoadButtons) do
          if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            if b.cancel then
              state.ui._saveLoadMode = nil
              return
            end
            local slot = b.slot or 1
            if state.ui._saveLoadMode == 'save' then
              save.saveToSlot(state, slot)
              state.ui.promptText = string.format("Saved to slot %d.", slot)
              state.ui.promptT = 0
              state.ui.promptDuration = 2
              state.ui.promptSticky = false
              state.ui._saveLoadMode = nil
            else
              local ok, err = save.loadFromSlot(state, slot)
              if ok then
                state.ui.promptText = string.format("Loaded slot %d.", slot)
                state.ui.promptT = 0
                state.ui.promptDuration = 2
                state.ui.promptSticky = false
                state.ui._saveLoadMode = nil
              else
                state.ui.promptText = "Load failed: " .. tostring(err)
                state.ui.promptT = 0
                state.ui.promptDuration = 3
                state.ui.promptSticky = false
              end
            end
            return
          end
        end
      end
      handlePauseMenuClick(x, y)
    end
    return
  end

  if button == 2 then
    if state.ui.isPlacingBuilding then
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      state.ui._isFreeInitialBuilder = nil
      return
    elseif state.ui.isBuildMenuOpen then
      state.ui.isBuildMenuOpen = false
      return
    elseif state.ui.isPlacingRoad then
      state.ui.isPlacingRoad = false
      state.ui.roadStartTile = nil
      return
    else
      state.ui.selectedBuilding = nil
      return
    end
  end

  if button ~= 1 then return end

  if ui.isOverBuildButton(x, y) then
    state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
    if state.ui.isBuildMenuOpen then
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      state.ui.isPlacingRoad = false
      state.ui.roadStartTile = nil
      state.ui.isVillagersPanelOpen = false
    end
    return
  end

  if ui.isOverRoadButton(x, y) then
    state.ui.isPlacingRoad = not state.ui.isPlacingRoad
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
    state.ui.isBuildMenuOpen = false
    state.ui.roadStartTile = nil
    state.ui.isVillagersPanelOpen = false
    state.ui.isDemolishMode = false
    return
  end



  if ui.isOverVillagersButton(x, y) then
    state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
    state.ui.isBuildMenuOpen = false
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
    state.ui.isPlacingRoad = false
    state.ui.roadStartTile = nil
    return
  end

  if ui.isOverQueueButton(x, y) then
    state.ui.isBuildQueueOpen = not state.ui.isBuildQueueOpen
    state.ui.isPaused = false
    state.ui.isBuildMenuOpen = false
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
    state.ui.isPlacingRoad = false
    state.ui.roadStartTile = nil
    state.ui.isVillagersPanelOpen = false
    state.ui.isDemolishMode = false
    return
  end

  -- Build Queue row interactions when panel open (independent of selection)
  if state.ui.isBuildQueueOpen and state.ui._queueButtons then
    -- drag start
    if button == 1 and not state.ui._queueDrag then
      for _, row in ipairs(state.ui._queueButtons) do
        local rr = row.rowRect
        if rr and x >= rr.x and x <= rr.x + rr.w and y >= rr.y and y <= rr.y + rr.h then
          state.ui._queueDrag = { id = row.id, startY = y, offsetY = (y - rr.y) }
          break
        end
      end
    end
    for _, row in ipairs(state.ui._queueButtons) do
      local up, down, pause, remove, rr = row.up, row.down, row.pause, row.remove, row.rowRect
      -- handle buttons first (so rowRect doesn't swallow clicks)
      if up and x >= up.x and x <= up.x + up.w and y >= up.y and y <= up.y + up.h then
        -- move item up one spot in queue order
        local q = state.game.buildQueue
        if q then
          for i=2,#q do
            if q[i].id == row.id then
              local tmp = q[i-1]
              q[i-1] = q[i]
              q[i] = tmp
              break
            end
          end
        end
        return
      elseif down and x >= down.x and x <= down.x + down.w and y >= down.y and y <= down.y + down.h then
        -- move item down one spot in queue order
        local q = state.game.buildQueue
        if q then
          for i=1,#q-1 do
            if q[i].id == row.id then
              local tmp = q[i+1]
              q[i+1] = q[i]
              q[i] = tmp
              break
            end
          end
        end
        return
      elseif pause and x >= pause.x and x <= pause.x + pause.w and y >= pause.y and y <= pause.y + pause.h then
        for _, q in ipairs(state.game.buildQueue or {}) do if q.id == row.id then q.paused = not (q.paused or false) break end end
        return
      elseif remove and x >= remove.x and x <= remove.x + remove.w and y >= remove.y and y <= remove.y + remove.h then
        -- cancel building (refund per rules)
        local target
        for _, b in ipairs(state.game.buildings) do if b.id == row.id then target = b break end end
        if target then require('src.buildings').cancel(state, target) end
        return
      end
      if rr and x >= rr.x and x <= rr.x + rr.w and y >= rr.y and y <= rr.y + rr.h then
        -- click row to pan camera to that building
        local target
        for _, b in ipairs(state.game.buildings) do if b.id == row.id then target = b break end end
        if target then
          local TILE = C.TILE_SIZE
          local screenW, screenH = love.graphics.getDimensions()
          local worldX = target.tileX * TILE + TILE / 2
          local worldY = target.tileY * TILE + TILE / 2
          -- If queue panel is open, center the panel and align the building above it
          local targetScreenX = screenW / 2
          local targetScreenY = screenH / 2
          if state.ui.isBuildQueueOpen and state.ui._queueLayout then
            local qy = state.ui._queueLayout.y or (screenH/2 - 130)
            -- place building slightly above the top of the centered panel
            targetScreenY = math.max(40, qy - 40)
          end
          local sc = (state.camera.scale or 1)
          local newCamX = worldX - targetScreenX / sc
          local newCamY = worldY - targetScreenY / sc
          local maxCamX = math.max(0, state.world.tilesX * TILE - screenW / sc)
          local maxCamY = math.max(0, state.world.tilesY * TILE - screenH / sc)
          state.camera.x = utils.clamp(newCamX, 0, maxCamX)
          state.camera.y = utils.clamp(newCamY, 0, maxCamY)
          -- flash the building briefly
          target._flashT = 0.5
          -- set selection so the floating label appears above it
          state.ui.selectedBuilding = target
          return
        end
      end
    end
  end

     if state.ui.isBuildMenuOpen then
      local option = ui.getBuildMenuOptionAt(x, y)
      if option then
        state.ui.selectedBuildingType = option.key
        state.ui.isPlacingBuilding = true
        state.ui.isBuildMenuOpen = false
        state.ui._isFreeInitialBuilder = nil
        return
      else
        state.ui.isBuildMenuOpen = false
        return
      end
    end

  -- Local staffing buttons when a worker building is selected
  do
    local sel = state.ui.selectedBuilding
    if sel then
      -- staffing if present
      local add = sel._assignBtn
      local rem = sel._unassignBtn
      if add and x >= add.x and x <= add.x + add.w and y >= add.y and y <= add.y + add.h then
        buildings.assignOne(state, sel)
        return
      elseif rem and x >= rem.x and x <= rem.x + rem.w and y >= rem.y and y <= rem.y + rem.h then
        buildings.unassignOne(state, sel)
        return
      end
      -- demolish
      local d = sel._demolishBtn
      if d and x >= d.x and x <= d.x + d.w and y >= d.y and y <= d.y + d.h then
        -- queue a demolition job for builders
        local jobId = state.game.jobs._nextId
        state.game.jobs._nextId = jobId + 1
        table.insert(state.game.jobs.demolitions, { id = jobId, target = sel })
        state.ui.promptText = "Demolition queued."
        state.ui.promptT = 0
        state.ui.promptDuration = 2
        state.ui.promptSticky = false
        return
      end
      -- queue priority controls (if selected building is in queue)
      local qu = sel._queueUpBtn
      local qd = sel._queueDownBtn
      if qu and x >= qu.x and x <= qu.x + qu.w and y >= qu.y and y <= qu.y + qu.h then
        if sel.id and state.game.buildQueue then
          for _, q in ipairs(state.game.buildQueue) do if q.id == sel.id then q.priority = (q.priority or 0) - 1 break end end
        end
        return
      end
      if qd and x >= qd.x and x <= qd.x + qd.w and y >= qd.y and y <= qd.y + qd.h then
        if sel.id and state.game.buildQueue then
          for _, q in ipairs(state.game.buildQueue) do if q.id == sel.id then q.priority = (q.priority or 0) + 1 break end end
        end
        return
      end
      -- Build Queue row interactions when panel open
      if state.ui.isBuildQueueOpen and state.ui._queueButtons then
        for _, row in ipairs(state.ui._queueButtons) do
          local up, down, pause, remove, rr = row.up, row.down, row.pause, row.remove, row.rowRect
          if rr and x >= rr.x and x <= rr.x + rr.w and y >= rr.y and y <= rr.y + rr.h then
            -- click row to pan camera to that building
            local target
            for _, b in ipairs(state.game.buildings) do if b.id == row.id then target = b break end end
            if target then
              local TILE = C.TILE_SIZE
              local screenW, screenH = love.graphics.getDimensions()
              local worldX = target.tileX * TILE + TILE / 2
              local worldY = target.tileY * TILE + TILE / 2
              state.camera.x = utils.clamp(worldX - (screenW / state.camera.scale) / 2, 0, state.world.tilesX * TILE - (screenW / state.camera.scale))
              state.camera.y = utils.clamp(worldY - (screenH / state.camera.scale) / 2, 0, state.world.tilesY * TILE - (screenH / state.camera.scale))
              return
            end
          end
          if up and x >= up.x and x <= up.x + up.w and y >= up.y and y <= up.y + up.h then
            for _, q in ipairs(state.game.buildQueue or {}) do if q.id == row.id then q.priority = (q.priority or 0) - 1 break end end
            return
          elseif down and x >= down.x and x <= down.x + down.w and y >= down.y and y <= down.y + down.h then
            for _, q in ipairs(state.game.buildQueue or {}) do if q.id == row.id then q.priority = (q.priority or 0) + 1 break end end
            return
          elseif pause and x >= pause.x and x <= pause.x + pause.w and y >= pause.y and y <= pause.y + pause.h then
            for _, q in ipairs(state.game.buildQueue or {}) do if q.id == row.id then q.paused = not (q.paused or false) break end end
            return
          elseif remove and x >= remove.x and x <= remove.x + remove.w and y >= remove.y and y <= remove.y + remove.h then
            -- cancel building (refund per rules)
            local target
            for _, b in ipairs(state.game.buildings) do if b.id == row.id then target = b break end end
            if target then require('src.buildings').cancel(state, target) end
            return
          end
        end
      end
    end
  end

  -- Global villagers panel buttons
  if state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
    for _, entry in ipairs(state.ui._villagersPanelButtons) do
      local add = entry.add
      local rem = entry.rem
      if add and x >= add.x and x <= add.x + add.w and y >= add.y and y <= add.y + add.h then
        buildings.assignOne(state, entry.b)
        return
      elseif rem and x >= rem.x and x <= rem.x + rem.w and y >= rem.y and y <= rem.y + rem.h then
        buildings.unassignOne(state, entry.b)
        return
      end
    end
  end

  -- Speed buttons in HUD
  if state.ui._speedButtons then
    for _, btn in pairs(state.ui._speedButtons) do
      if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
        state.time.speed = btn.v
        return
      end
    end
  end

  -- Food HUD click
  if state.ui._foodButton then
    local fb = state.ui._foodButton
    if x >= fb.x and x <= fb.x + fb.w and y >= fb.y and y <= fb.y + fb.h then
      state.ui.isFoodPanelOpen = true
      state.ui.isPaused = true
      return
    end
  end

  -- Minimap click-to-navigate
  local mm = state.ui._miniMap
  if mm and x >= mm.x and x <= mm.x + mm.w and y >= mm.y and y <= mm.y + mm.h then
    local TILE = C.TILE_SIZE
    local screenW, screenH = love.graphics.getDimensions()
    local worldX = (x - mm.x) / mm.scale * TILE
    local worldY = (y - mm.y) / mm.scale * TILE
    state.camera.x = utils.clamp(worldX - (screenW / state.camera.scale) / 2, 0, state.world.tilesX * TILE - (screenW / state.camera.scale))
    state.camera.y = utils.clamp(worldY - (screenH / state.camera.scale) / 2, 0, state.world.tilesY * TILE - (screenH / state.camera.scale))
    return
  end

  if state.ui.isPlacingRoad then
    local tx, ty = screenToTile(x, y)
    if not state.ui.roadStartTile then
      -- Snap start to a placeable neighbor if clicked on a blocked tile (e.g., a building)
      if not roads.canPlaceAt(state, tx, ty) then
        local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
        local snappedX, snappedY = tx, ty
        -- Prefer neighbor that leads toward mouse direction if possible
        local mx, my = getMouseTile()
        local prefer = { 0, 0 }
        prefer[1] = (mx > tx) and 1 or ((mx < tx) and -1 or 0)
        prefer[2] = (my > ty) and 1 or ((my < ty) and -1 or 0)
        -- Try preferred axis first
        local try = {}
        if prefer[1] ~= 0 then table.insert(try, { prefer[1], 0 }) end
        if prefer[2] ~= 0 then table.insert(try, { 0, prefer[2] }) end
        for i=1,#dirs do table.insert(try, dirs[i]) end
        for i=1,#try do
          local nx, ny = tx + try[i][1], ty + try[i][2]
          if roads.canPlaceAt(state, nx, ny) then snappedX, snappedY = nx, ny; break end
        end
        state.ui.roadStartTile = { x = snappedX, y = snappedY }
      else
        state.ui.roadStartTile = { x = tx, y = ty }
      end
      return
    else
      local sx, sy = state.ui.roadStartTile.x, state.ui.roadStartTile.y
      local path = roads.computePath(state, sx, sy, tx, ty)
      -- Include start tile so the road begins at the snapped starting cell
      if roads.canPlaceAt(state, sx, sy) and not roads.hasRoad(state, sx, sy) then
        table.insert(path, 1, { x = sx, y = sy })
      end
      roads.placePath(state, path)
      state.ui.roadStartTile = { x = tx, y = ty }
      return
    end
  end

  if not state.ui.isPlacingBuilding then
    local tileX, tileY = screenToTile(x, y)
    local b = hitTestBuildingAt(state, tileX, tileY)
    if state.ui.isDemolishMode and b then
      if buildings.demolish(state, b) then
        state.ui.promptText = "Building demolished (+50% wood)."
        state.ui.promptT = 0
        state.ui.promptDuration = 2
        state.ui.promptSticky = false
      end
      return
    end
    state.ui.selectedBuilding = b
    if b then return end
  end

  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    local tileX, tileY = screenToTile(x, y)
    if not isOverUI(x, y)
      and buildings.canPlaceAt(state, tileX, tileY) then
      local newB = buildings.place(state, state.ui.selectedBuildingType, tileX, tileY)
      if newB and newB.type == 'builder' and state.ui._pauseTimeForInitial then
        -- Instantly complete the initial builder and grant residents (capacity was added on placement)
        newB.construction.progress = newB.construction.required
        newB.construction.complete = true
        local res = state.buildingDefs.builder.residents or 0
        state.game.population.total = (state.game.population.total or 0) + res
        state.ui._isFreeInitialBuilder = nil
        state.ui._pauseTimeForInitial = nil
        -- Clear initial long prompt and show ready prompt
        state.ui.prompts = state.ui.prompts or {}
        -- hard clear all existing prompts to avoid lingering initial prompt
        state.ui.prompts = {}
        state.ui.promptText = nil
        state.ui.promptDuration = 0
        state.ui._promptUseRealTime = nil
        table.insert(state.ui.prompts, { text = "Your Builders Workplace is ready. The first day begins!", t = 0, duration = 5, useRealTime = true })
        -- Start time at morning
        state.time.t = state.time.dayLength * 0.25
        state.time.normalized = state.time.t / state.time.dayLength
      end
      -- Mark any normal placed building as planned (builders will start when resources are available)
      if newB and not state.ui._isFreeInitialBuilder then
        newB.construction = newB.construction or {}
        newB.construction.waitingForResources = true
        -- Ensure it is in the build queue
        state.game.buildQueue = state.game.buildQueue or {}
        local exists = false
        for _, q in ipairs(state.game.buildQueue) do if q.id == newB.id then exists = true; break end end
        if not exists then table.insert(state.game.buildQueue, { id = newB.id, priority = 0, paused = false }) end
      end
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      return
    end
  end
end

function love.keypressed(key)
  if state.ui._isFreeInitialBuilder then
    return
  end
  if key == 'escape' then
    if state.ui.isBuildMenuOpen then
      state.ui.isBuildMenuOpen = false
    elseif state.ui.isFoodPanelOpen then
      state.ui.isFoodPanelOpen = false
      state.ui.isPaused = false
    else
      if state.ui.isPlacingBuilding then
        state.ui.isPlacingBuilding = false
        state.ui.selectedBuildingType = nil
      elseif state.ui.isPlacingRoad then
        state.ui.isPlacingRoad = false
        state.ui.roadStartTile = nil
      else
        state.ui.isPaused = not state.ui.isPaused
      end
    end
  elseif key == 'c' then
    state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
    if state.ui.isBuildMenuOpen then
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
    end
  elseif key == 'f' then
    state.ui.isFoodPanelOpen = not state.ui.isFoodPanelOpen
    return
  elseif key == 'r' then
    state.ui.isPlacingRoad = not state.ui.isPlacingRoad
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
  elseif key == 'v' then
    state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
  elseif key == 'q' then
    -- Toggle build queue only; do not open pause menu
    state.ui.isBuildQueueOpen = not state.ui.isBuildQueueOpen
    state.ui.isPaused = false
    if state.ui.isBuildQueueOpen then
      -- close other panels/modes for clarity
      state.ui.isBuildMenuOpen = false
      state.ui.isVillagersPanelOpen = false
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      state.ui.isPlacingRoad = false
      state.ui.roadStartTile = nil
    end
    return
  elseif key == '1' then
    state.time.speed = 1
  elseif key == '2' then
    state.time.speed = 2
  elseif key == '3' then
    state.time.speed = 4
  elseif key == '4' then
    state.time.speed = 8
  elseif key == '+' or key == '=' then
    state.camera.scale = math.min(state.camera.maxScale or 2.5, (state.camera.scale or 1) + 0.1)
  elseif key == '-' then
    state.camera.scale = math.max(state.camera.minScale or 0.5, (state.camera.scale or 1) - 0.1)
  elseif key == 'g' then
    state.ui.forceGrid = not state.ui.forceGrid
  elseif key == 'F5' or key == 's' and (love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl')) then
    save.saveToSlot(state, 1)
    state.ui.promptText = "Game saved."
    state.ui.promptT = 0
    state.ui.promptDuration = 2
    state.ui.promptSticky = false
  elseif key == 'F9' or key == 'l' and (love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl')) then
    local ok, err = save.loadFromSlot(state, 1)
    if ok then
      state.ui.promptText = "Game loaded."
      state.ui.promptT = 0
      state.ui.promptDuration = 2
      state.ui.promptSticky = false
    else
      state.ui.promptText = "Load failed: " .. tostring(err)
      state.ui.promptT = 0
      state.ui.promptDuration = 3
      state.ui.promptSticky = false
    end
  end

  -- Build menu quick shortcuts
  if state.ui.isBuildMenuOpen then
    local map = { h = 'house', l = 'lumberyard', w = 'warehouse', b = 'builder', f = 'farm' }
    local sel = map[key]
    if sel then
      state.ui.selectedBuildingType = sel
      state.ui.isPlacingBuilding = true
      state.ui.isBuildMenuOpen = false
    end
  end
end

function love.wheelmoved(dx, dy)
  if dy == 0 then return end
  local oldScale = state.camera.scale
  local newScale = utils.clamp(oldScale * (1 + dy * 0.1), state.camera.minScale, state.camera.maxScale)
  if math.abs(newScale - oldScale) < 1e-4 then return end

  -- Zoom around mouse position
  local mx, my = love.mouse.getPosition()
  local preWorldX = state.camera.x + mx / oldScale
  local preWorldY = state.camera.y + my / oldScale
  state.camera.scale = newScale
  state.camera.x = preWorldX - mx / newScale
  state.camera.y = preWorldY - my / newScale

  -- Clamp after zoom
  local screenW, screenH = love.graphics.getDimensions()
  local maxCamX = math.max(0, state.world.tilesX * TILE_SIZE - screenW / state.camera.scale)
  local maxCamY = math.max(0, state.world.tilesY * TILE_SIZE - screenH / state.camera.scale)
  state.camera.x = utils.clamp(state.camera.x, 0, maxCamX)
  state.camera.y = utils.clamp(state.camera.y, 0, maxCamY)
end 

function love.mousereleased(x, y, button)
  if state.ui.isBuildQueueOpen and state.ui._queueDrag then
    local drag = state.ui._queueDrag
    local dropIndex = state.ui._queueDropIndex
    state.ui._queueDrag = nil
    state.ui._queueDropIndex = nil
    if dropIndex and drag and drag.id and state.game.buildQueue then
      local q = state.game.buildQueue
      local cur
      for i=1,#q do if q[i].id == drag.id then cur = i; break end end
      if cur then
        local item = table.remove(q, cur)
        if cur < dropIndex then dropIndex = math.max(1, dropIndex - 1) end
        table.insert(q, math.max(1, math.min(dropIndex, #q + 1)), item)
      end
    end
    return
  end
end