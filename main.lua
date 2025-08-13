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
local roads = require('src.roads')

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
    and (state.ui._isFreeInitialBuilder or buildings.canAfford(state, state.ui.selectedBuildingType))

  -- Show lumberyard radius while previewing
  if state.ui.selectedBuildingType == 'lumberyard' then
    local def = state.buildingDefs.lumberyard
    local radiusPx = def.radiusTiles * TILE_SIZE
    local cx = px + TILE_SIZE / 2
    local cy = py + TILE_SIZE / 2
    love.graphics.setColor(colors.radius)
    love.graphics.circle('fill', cx, cy, radiusPx)
    love.graphics.setColor(colors.radiusOutline)
    love.graphics.circle('line', cx, cy, radiusPx)
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
      elseif opt.key == 'restart' then
        state.restart()
        trees.generate(state)
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
  if state.ui.isPaused or state.ui.isBuildMenuOpen or state.ui.isVillagersPanelOpen then return end
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
      else
        -- entering night: remember current speed then switch to 8x
        state.time.preNightSpeed = state.time.speed or 1
        state.time.speed = 8
      end
      state.time.lastIsDay = isDay
    end
  end

  -- Time of day (apply time speed)
  local sdt = dt * (state.time.speed or 1)
  if not isInitial then
    state.time.t = (state.time.t + sdt) % state.time.dayLength
    state.time.normalized = state.time.t / state.time.dayLength
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
      state.ui.promptText = text
      state.ui.promptT = 0
      state.ui.promptDuration = 9999
      state.ui.promptSticky = false
      state.ui._lastCapacityPrompted = cap
    else
      -- Not full anymore or still in initial placement; clear prompt
      if state.ui.promptText and state.ui._lastCapacityPrompted then
        state.ui.promptText = nil
        state.ui.promptDuration = 0
        state.ui.promptSticky = false
      end
    end
  end

  -- Systems
  if not isInitial then
    workers.update(state, sdt)
  end
  buildings.update(state, sdt)
  particles.update(state.game.particles, sdt)
  trees.updateShake(state, sdt)

  -- Preview timer for pulsing outline
  state.ui.previewT = state.ui.previewT + sdt
  -- Prompt timer
  if state.ui.promptText and state.ui.promptDuration and state.ui.promptDuration > 0 then
    state.ui.promptT = (state.ui.promptT or 0) + sdt
    if state.ui.promptT > state.ui.promptDuration then
      state.ui.promptText = nil
      state.ui.promptT = 0
      state.ui.promptDuration = 0
    end
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
    roads.drawPreview(state, path)
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
  ui.drawMiniMap(state)
  ui.drawPrompt(state)

  local sel = state.ui.selectedBuilding
  if sel and (sel.type == 'lumberyard' or sel.type == 'builder') then
    local mx, my = 16, love.graphics.getHeight() - 90
    local panelW, panelH = 360, 70
    love.graphics.setColor(colors.uiPanel)
    love.graphics.rectangle('fill', mx, my, panelW, panelH, 8, 8)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle('line', mx, my, panelW, panelH, 8, 8)

    love.graphics.setColor(colors.text)
    local maxSlots = (sel.type == 'lumberyard') and (state.buildingDefs.lumberyard.numWorkers or 0) or (state.buildingDefs.builder.numWorkers or 0)
    local label = (sel.type == 'lumberyard') and 'Lumberyard workers' or 'Builder workers'
    love.graphics.print(string.format('%s: %d / %d', label, sel.assigned or 0, maxSlots), mx + 12, my + 12)
    love.graphics.print(string.format('Population: %d total, %d assigned', state.game.population.total or 0, state.game.population.assigned or 0), mx + 12, my + 30)

    local btnW, btnH = 32, 28
    local remX, remY = mx + panelW - 80, my + 12
    local addX, addY = mx + panelW - 40, my + 12

    local function drawBtn(x, y, label)
      love.graphics.setColor(colors.button)
      love.graphics.rectangle('fill', x, y, btnW, btnH, 6, 6)
      love.graphics.setColor(colors.uiPanelOutline)
      love.graphics.rectangle('line', x, y, btnW, btnH, 6, 6)
      love.graphics.setColor(colors.text)
      love.graphics.printf(label, x, y + 6, btnW, 'center')
    end

    drawBtn(remX, remY, '-')
    drawBtn(addX, addY, '+')

    sel._assignBtn = { x = addX, y = addY, w = btnW, h = btnH }
    sel._unassignBtn = { x = remX, y = remY, w = btnW, h = btnH }
  end

  if not state.ui.isPaused and not state.ui.isBuildMenuOpen then
    love.graphics.setColor(colors.text)
    local hintY = love.graphics.getHeight() - 24
    love.graphics.print("Click 'Build' -> choose 'House' or 'Lumberyard' -> place on the map. Move mouse to screen edges to pan. Right click to cancel placement.", 16, hintY)
  end

  ui.drawPauseMenu(state)
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
    if button == 1 then handlePauseMenuClick(x, y) end
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
    if sel and (sel.type == 'lumberyard' or sel.type == 'builder') then
      local add = sel._assignBtn
      local rem = sel._unassignBtn
      if add and x >= add.x and x <= add.x + add.w and y >= add.y and y <= add.y + add.h then
        buildings.assignOne(state, sel)
        return
      elseif rem and x >= rem.x and x <= rem.x + rem.w and y >= rem.y and y <= rem.y + rem.h then
        buildings.unassignOne(state, sel)
        return
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
      state.ui.roadStartTile = { x = tx, y = ty }
      return
    else
      local sx, sy = state.ui.roadStartTile.x, state.ui.roadStartTile.y
      local path = roads.computePath(state, sx, sy, tx, ty)
      roads.placePath(state, path)
      state.ui.roadStartTile = { x = tx, y = ty }
      return
    end
  end

  if not state.ui.isPlacingBuilding then
    local tileX, tileY = screenToTile(x, y)
    local b = hitTestBuildingAt(state, tileX, tileY)
    state.ui.selectedBuilding = b
    if b then return end
  end

  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    local tileX, tileY = screenToTile(x, y)
    if not isOverUI(x, y)
      and buildings.canPlaceAt(state, tileX, tileY)
      and (state.ui._isFreeInitialBuilder or buildings.canAfford(state, state.ui.selectedBuildingType)) then
      if not state.ui._isFreeInitialBuilder then
        buildings.payCost(state, state.ui.selectedBuildingType)
      end
      local newB = buildings.place(state, state.ui.selectedBuildingType, tileX, tileY)
      if state.ui._isFreeInitialBuilder and newB and newB.type == 'builder' then
        -- Instantly complete the initial builder and grant residents (capacity was added on placement)
        newB.construction.progress = newB.construction.required
        newB.construction.complete = true
        local res = state.buildingDefs.builder.residents or 0
        state.game.population.total = (state.game.population.total or 0) + res
        state.ui._isFreeInitialBuilder = nil
        state.ui._pauseTimeForInitial = nil
        -- Prompt player and start first day
        state.ui.promptText = "Your Builders Workplace is ready. The first day begins!"
        state.ui.promptT = 0
        state.ui.promptDuration = 5
        -- Start time at morning
        state.time.t = state.time.dayLength * 0.25
        state.time.normalized = state.time.t / state.time.dayLength
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
  elseif key == 'r' then
    state.ui.isPlacingRoad = not state.ui.isPlacingRoad
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
  elseif key == 'v' then
    state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
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
  end

  -- Build menu quick shortcuts
  if state.ui.isBuildMenuOpen then
    local map = { h = 'house', l = 'lumberyard', w = 'warehouse', b = 'builder' }
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