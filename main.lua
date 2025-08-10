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
  local worldX = state.camera.x + mx
  local worldY = state.camera.y + my
  local tileX = math.floor(worldX / TILE_SIZE)
  local tileY = math.floor(worldY / TILE_SIZE)
  return tileX, tileY
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

-- Draw a placement preview at mouse tile, including lumberyard radius
local function drawPlacementPreview()
  if state.ui.isPaused then return end
  if not state.ui.isPlacingBuilding or not state.ui.selectedBuildingType then return end

  local tileX, tileY = getMouseTile()
  local px = tileX * TILE_SIZE
  local py = tileY * TILE_SIZE

  local isValid = buildings.canPlaceAt(state, tileX, tileY)
    and not isOverUI(love.mouse.getX(), love.mouse.getY())
    and buildings.canAfford(state, state.ui.selectedBuildingType)

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
end

function love.update(dt)
  if state.ui.isPaused or state.ui.isBuildMenuOpen then return end

  -- Passive production placeholder (none currently for lumberyard)
  state.game.productionRates.wood = 0

  -- Systems
  workers.update(state, dt)
  buildings.update(state, dt)
  particles.update(state.game.particles, dt)
  trees.updateShake(state, dt)

  -- Preview timer for pulsing outline
  state.ui.previewT = state.ui.previewT + dt

  -- Mouse edge panning
  local mx, my = love.mouse.getPosition()
  local screenW, screenH = love.graphics.getDimensions()
  local margin = 24
  local dx, dy = 0, 0
  if mx <= margin then dx = -1 end
  if mx >= screenW - margin then dx = 1 end
  if my <= margin then dy = -1 end
  if my >= screenH - margin then dy = 1 end

  state.camera.x = state.camera.x + dx * state.camera.panSpeed * dt
  state.camera.y = state.camera.y + dy * state.camera.panSpeed * dt

  local maxCamX = math.max(0, state.world.tilesX * TILE_SIZE - screenW)
  local maxCamY = math.max(0, state.world.tilesY * TILE_SIZE - screenH)
  state.camera.x = utils.clamp(state.camera.x, 0, maxCamX)
  state.camera.y = utils.clamp(state.camera.y, 0, maxCamY)
end

function love.draw()
  -- World space draw
  love.graphics.push()
  love.graphics.translate(-state.camera.x, -state.camera.y)

  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    grid.draw(state)
  end
  buildings.drawSelectedRadius(state)
  trees.draw(state)
  roads.draw(state)
  buildings.drawAll(state)
  workers.draw(state)

  -- Dim the world during placement preview (but keep the preview bright)
  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    local screenW, screenH = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle('fill', state.camera.x, state.camera.y, screenW, screenH)
  end

  -- Road preview
  if state.ui.isPlacingRoad and state.ui.roadStartTile then
    local sx, sy = state.ui.roadStartTile.x, state.ui.roadStartTile.y
    local ex, ey = getMouseTile()
    local path = roads.computePath(state, sx, sy, ex, ey)
    roads.drawPreview(state, path)
  end

  drawPlacementPreview()
  particles.draw(state.game.particles)

  love.graphics.pop()

  -- UI draw
  ui.drawTopButtons(state)
  ui.drawBuildMenu(state, state.buildingDefs)
  ui.drawHUD(state)

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
  -- If pause menu is open (not build overlay), route to pause menu
  if state.ui.isPaused and not state.ui.isBuildMenuOpen then
    if button == 1 then handlePauseMenuClick(x, y) end
    return
  end

  -- Right click cancels placement or closes build menu or deselects or cancels road mode
  if button == 2 then
    if state.ui.isPlacingBuilding then
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
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

  -- Toggle build overlay
  if ui.isOverBuildButton(x, y) then
    state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
    if state.ui.isBuildMenuOpen then
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      state.ui.isPlacingRoad = false
      state.ui.roadStartTile = nil
    end
    return
  end

  -- Toggle road mode
  if ui.isOverRoadButton(x, y) then
    state.ui.isPlacingRoad = not state.ui.isPlacingRoad
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
    state.ui.isBuildMenuOpen = false
    state.ui.roadStartTile = nil
    return
  end

  -- Handle clicks on build menu
  if state.ui.isBuildMenuOpen then
    local option = ui.getBuildMenuOptionAt(x, y)
    if option then
      state.ui.selectedBuildingType = option.key
      state.ui.isPlacingBuilding = true
      state.ui.isBuildMenuOpen = false
      return
    else
      state.ui.isBuildMenuOpen = false
      return
    end
  end

  -- Road placement start or apply
  if state.ui.isPlacingRoad then
    local tx, ty = getMouseTile()
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

  -- If not placing, try selecting a building
  if not state.ui.isPlacingBuilding then
    local tileX, tileY = getMouseTile()
    local b = hitTestBuildingAt(state, tileX, tileY)
    state.ui.selectedBuilding = b
    if b then return end
  end

  -- Handle placement
  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType then
    local tileX, tileY = getMouseTile()
    if not isOverUI(x, y)
      and buildings.canPlaceAt(state, tileX, tileY)
      and buildings.canAfford(state, state.ui.selectedBuildingType) then
      buildings.payCost(state, state.ui.selectedBuildingType)
      local newB = buildings.place(state, state.ui.selectedBuildingType, tileX, tileY)
      if newB.type == 'lumberyard' then
        workers.spawnForLumberyard(state, newB)
      end
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      return
    end
  end
end

function love.keypressed(key)
  if key == 'escape' then
    if state.ui.isBuildMenuOpen then
      state.ui.isBuildMenuOpen = false
      return
    end
    state.ui.isPaused = not state.ui.isPaused
    return
  end
end 