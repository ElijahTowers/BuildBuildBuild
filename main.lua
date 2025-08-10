local TILE_SIZE = 32

local uiState = {
  isBuildMenuOpen = false,
  isPlacingBuilding = false,
  selectedBuildingType = nil,
  isPaused = false
}

-- Camera and world
local camera = { x = 0, y = 0, panSpeed = 700 }
local world = { tilesX = 0, tilesY = 0 }

-- Pause menu definition
local pauseMenu = {
  width = 360,
  optionHeight = 48,
  optionSpacing = 10,
  options = {
    { key = "resume", label = "Resume" },
    { key = "restart", label = "Restart" },
    { key = "quit", label = "Quit" }
  }
}

local buildButton = {
  x = 16,
  y = 16,
  width = 120,
  height = 40,
  label = "Build"
}

local buildMenu = {
  x = 16,
  y = 72,
  width = 220,
  height = 120,
  options = {
    { key = "house", label = "House", color = { 0.9, 0.6, 0.2, 1.0 } },
    { key = "lumberyard", label = "Lumberyard", color = { 0.3, 0.7, 0.3, 1.0 } }
  }
}

local colors = {
  background = { 0.12, 0.12, 0.14, 1.0 },
  grid = { 0.22, 0.22, 0.25, 1.0 },
  uiPanel = { 0.15, 0.15, 0.18, 1.0 },
  uiPanelOutline = { 1, 1, 1, 0.08 },
  button = { 0.20, 0.20, 0.24, 1.0 },
  buttonHover = { 0.26, 0.26, 0.30, 1.0 },
  text = { 0.92, 0.92, 0.95, 1.0 },
  preview = { 1.0, 1.0, 1.0, 0.35 },
  invalid = { 0.9, 0.2, 0.2, 0.35 },
  outline = { 1.0, 1.0, 1.0, 0.3 },
  treeFill = { 0.15, 0.55, 0.20, 1.0 },
  treeOutline = { 0.08, 0.25, 0.10, 0.7 },
  radius = { 0.3, 0.7, 0.3, 0.12 },
  radiusOutline = { 0.35, 0.8, 0.35, 0.25 }
}

local buildings = {}

-- Trees
local trees = {}

-- Building definitions: cost and active chopping behavior
local buildingDefs = {
  house = {
    cost = { wood = 10 },
    production = nil
  },
  lumberyard = {
    cost = { wood = 20 },
    production = nil, -- replaced by active chopping
    radiusTiles = 6,   -- chopping radius in tiles
    chopRate = 1.0,    -- tree health per second
    woodPerTree = 6    -- wood gained per felled tree
  }
}

-- Game state: resources and cached production rates for HUD
local gameState = {
  resources = { wood = 50 },
  productionRates = { wood = 0 }
}

local function isPointInRect(px, py, rx, ry, rw, rh)
  return px >= rx and px <= (rx + rw) and py >= ry and py <= (ry + rh)
end

local function getMouseTile()
  local mx, my = love.mouse.getX(), love.mouse.getY()
  local worldX = camera.x + mx
  local worldY = camera.y + my
  local tileX = math.floor(worldX / TILE_SIZE)
  local tileY = math.floor(worldY / TILE_SIZE)
  return tileX, tileY
end

local function isOverUI(mx, my)
  if isPointInRect(mx, my, buildButton.x, buildButton.y, buildButton.width, buildButton.height) then
    return true
  end
  if uiState.isBuildMenuOpen then
    if isPointInRect(mx, my, buildMenu.x, buildMenu.y, buildMenu.width, buildMenu.height) then
      return true
    end
  end
  return false
end

local function isTreeAt(tileX, tileY)
  for index, t in ipairs(trees) do
    if t.alive and t.tileX == tileX and t.tileY == tileY then
      return index
    end
  end
  return nil
end

local function canPlaceAt(tileX, tileY)
  -- Bounds check
  if tileX < 0 or tileY < 0 or tileX >= world.tilesX or tileY >= world.tilesY then
    return false
  end
  for _, b in ipairs(buildings) do
    if b.tileX == tileX and b.tileY == tileY then
      return false
    end
  end
  if isTreeAt(tileX, tileY) then
    return false
  end
  return true
end

local function canAfford(buildingType)
  local def = buildingDefs[buildingType]
  if not def or not def.cost then return true end
  for resourceName, amount in pairs(def.cost) do
    local current = gameState.resources[resourceName] or 0
    if current < amount then return false end
  end
  return true
end

local function payCost(buildingType)
  local def = buildingDefs[buildingType]
  if not def or not def.cost then return end
  for resourceName, amount in pairs(def.cost) do
    local current = gameState.resources[resourceName] or 0
    gameState.resources[resourceName] = math.max(0, current - amount)
  end
end

local function placeBuilding(selectedType, tileX, tileY)
  local color
  if selectedType == "house" then
    color = { 0.9, 0.6, 0.2, 1.0 }
  elseif selectedType == "lumberyard" then
    color = { 0.3, 0.7, 0.3, 1.0 }
  else
    color = { 0.7, 0.7, 0.7, 1.0 }
  end

  local newBuilding = {
    type = selectedType,
    tileX = tileX,
    tileY = tileY,
    color = color
  }

  -- Initialize chopping state for lumberyard
  if selectedType == "lumberyard" then
    newBuilding.chopTargetIndex = nil
  end

  table.insert(buildings, newBuilding)
end

local function drawGrid()
  local screenW, screenH = love.graphics.getDimensions()
  local startTileX = math.max(0, math.floor(camera.x / TILE_SIZE))
  local endTileX = math.min(world.tilesX, math.ceil((camera.x + screenW) / TILE_SIZE))
  local startTileY = math.max(0, math.floor(camera.y / TILE_SIZE))
  local endTileY = math.min(world.tilesY, math.ceil((camera.y + screenH) / TILE_SIZE))

  love.graphics.setColor(colors.grid)
  for tx = startTileX, endTileX do
    local x = tx * TILE_SIZE
    love.graphics.line(x, startTileY * TILE_SIZE, x, endTileY * TILE_SIZE)
  end
  for ty = startTileY, endTileY do
    local y = ty * TILE_SIZE
    love.graphics.line(startTileX * TILE_SIZE, y, endTileX * TILE_SIZE, y)
  end
end

local function drawButton(button)
  local mx, my = love.mouse.getPosition()
  local hovered = isPointInRect(mx, my, button.x, button.y, button.width, button.height)
  love.graphics.setColor(hovered and colors.buttonHover or colors.button)
  love.graphics.rectangle("fill", button.x, button.y, button.width, button.height, 6, 6)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", button.x, button.y, button.width, button.height, 6, 6)

  love.graphics.setColor(colors.text)
  love.graphics.printf(button.label, button.x, button.y + 12, button.width, "center")
end

local function drawBuildMenu()
  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle("fill", buildMenu.x, buildMenu.y, buildMenu.width, buildMenu.height, 8, 8)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", buildMenu.x, buildMenu.y, buildMenu.width, buildMenu.height, 8, 8)

  local optionHeight = 48
  for index, option in ipairs(buildMenu.options) do
    local ox = buildMenu.x + 12
    local oy = buildMenu.y + 12 + (index - 1) * (optionHeight + 8)
    local ow = buildMenu.width - 24
    local oh = optionHeight

    local mx, my = love.mouse.getPosition()
    local hovered = isPointInRect(mx, my, ox, oy, ow, oh)

    love.graphics.setColor(hovered and colors.buttonHover or colors.button)
    love.graphics.rectangle("fill", ox, oy, ow, oh, 6, 6)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle("line", ox, oy, ow, oh, 6, 6)

    love.graphics.setColor(option.color)
    love.graphics.rectangle("fill", ox + 10, oy + 8, 32, 32, 4, 4)

    love.graphics.setColor(colors.text)
    local def = buildingDefs[option.key]
    local costText = ""
    if def and def.cost and def.cost.wood then
      costText = string.format(" (Cost: %d wood)", def.cost.wood)
    end
    love.graphics.print(option.label .. costText, ox + 52, oy + 12)
  end
end

local function getMenuOptionAt(mx, my)
  local optionHeight = 48
  for index, option in ipairs(buildMenu.options) do
    local ox = buildMenu.x + 12
    local oy = buildMenu.y + 12 + (index - 1) * (optionHeight + 8)
    local ow = buildMenu.width - 24
    local oh = optionHeight
    if isPointInRect(mx, my, ox, oy, ow, oh) then
      return option
    end
  end
  return nil
end

local function drawTrees()
  for _, t in ipairs(trees) do
    if t.alive then
      local cx = t.tileX * TILE_SIZE + TILE_SIZE / 2
      local cy = t.tileY * TILE_SIZE + TILE_SIZE / 2
      local r = TILE_SIZE * 0.4
      love.graphics.setColor(colors.treeFill)
      love.graphics.circle("fill", cx, cy, r)
      love.graphics.setColor(colors.treeOutline)
      love.graphics.circle("line", cx, cy, r)
    end
  end
end

local function drawLumberyardRadii()
  for _, b in ipairs(buildings) do
    if b.type == "lumberyard" then
      local def = buildingDefs.lumberyard
      local radiusPx = def.radiusTiles * TILE_SIZE
      local cx = b.tileX * TILE_SIZE + TILE_SIZE / 2
      local cy = b.tileY * TILE_SIZE + TILE_SIZE / 2
      love.graphics.setColor(colors.radius)
      love.graphics.circle("fill", cx, cy, radiusPx)
      love.graphics.setColor(colors.radiusOutline)
      love.graphics.circle("line", cx, cy, radiusPx)
    end
  end
end

local function drawBuildings()
  for _, b in ipairs(buildings) do
    local px = b.tileX * TILE_SIZE
    local py = b.tileY * TILE_SIZE
    love.graphics.setColor(b.color)
    love.graphics.rectangle("fill", px, py, TILE_SIZE, TILE_SIZE, 4, 4)

    love.graphics.setColor(colors.outline)
    love.graphics.rectangle("line", px, py, TILE_SIZE, TILE_SIZE, 4, 4)
  end
end

local function drawPlacementPreview()
  if uiState.isPaused then return end
  if not uiState.isPlacingBuilding or not uiState.selectedBuildingType then
    return
  end

  local tileX, tileY = getMouseTile()
  local px = tileX * TILE_SIZE
  local py = tileY * TILE_SIZE

  local isValid = canPlaceAt(tileX, tileY) and not isOverUI(love.mouse.getX(), love.mouse.getY()) and canAfford(uiState.selectedBuildingType)

  if not isValid then
    love.graphics.setColor(colors.invalid)
  else
    if uiState.selectedBuildingType == "house" then
      love.graphics.setColor(0.9, 0.6, 0.2, colors.preview[4])
    elseif uiState.selectedBuildingType == "lumberyard" then
      love.graphics.setColor(0.3, 0.7, 0.3, colors.preview[4])
    else
      love.graphics.setColor(colors.preview)
    end
  end

  love.graphics.rectangle("fill", px, py, TILE_SIZE, TILE_SIZE, 4, 4)
  love.graphics.setColor(colors.outline)
  love.graphics.rectangle("line", px, py, TILE_SIZE, TILE_SIZE, 4, 4)
end

local function getTotalProductionPerSecond()
  -- Only passive production counted here; lumberyards use active chopping -> 0 by default
  local totals = { wood = 0 }
  for _, b in ipairs(buildings) do
    local def = buildingDefs[b.type]
    if def and def.production then
      for resourceName, amount in pairs(def.production) do
        totals[resourceName] = (totals[resourceName] or 0) + amount
      end
    end
  end
  return totals
end

local function drawHUD()
  local x = buildButton.x + buildButton.width + 16
  local y = 16
  local w = 300
  local h = 68

  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)

  love.graphics.setColor(colors.text)
  local wood = math.floor(gameState.resources.wood + 0.5)
  local woodRate = gameState.productionRates.wood or 0
  love.graphics.print(string.format("Wood: %d  (+%.1f/s passive)", wood, woodRate), x + 12, y + 12)

  if uiState.isPlacingBuilding and uiState.selectedBuildingType and not uiState.isPaused then
    local def = buildingDefs[uiState.selectedBuildingType]
    if def and def.cost and def.cost.wood then
      local can = canAfford(uiState.selectedBuildingType)
      local costStr = string.format("Cost: %d wood", def.cost.wood)
      if not can then
        love.graphics.setColor(0.95, 0.45, 0.45, 1)
      else
        love.graphics.setColor(colors.text)
      end
      love.graphics.print(costStr, x + 12, y + 30)
    end

    if uiState.selectedBuildingType == "lumberyard" then
      love.graphics.setColor(colors.text)
      love.graphics.print(string.format("Radius: %d tiles", buildingDefs.lumberyard.radiusTiles), x + 12, y + 48)
    end
  end
end

local function restartGame()
  buildings = {}
  trees = {}
  gameState.resources = { wood = 50 }
  gameState.productionRates = { wood = 0 }
  uiState.isBuildMenuOpen = false
  uiState.isPlacingBuilding = false
  uiState.selectedBuildingType = nil
  uiState.isPaused = false
  camera.x, camera.y = 0, 0
  generateTrees()
end

local function drawPauseMenu()
  if not uiState.isPaused then return end

  local screenW, screenH = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)

  local contentHeight = #pauseMenu.options * pauseMenu.optionHeight + (#pauseMenu.options - 1) * pauseMenu.optionSpacing
  local panelW = pauseMenu.width
  local panelH = contentHeight + 40
  local panelX = (screenW - panelW) / 2
  local panelY = (screenH - panelH) / 2

  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 10, 10)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 10, 10)

  local ox = panelX + 20
  local oy = panelY + 20
  for i, opt in ipairs(pauseMenu.options) do
    local btnY = oy + (i - 1) * (pauseMenu.optionHeight + pauseMenu.optionSpacing)
    local btnW = panelW - 40
    local btnH = pauseMenu.optionHeight
    local mx, my = love.mouse.getPosition()
    local hovered = isPointInRect(mx, my, ox, btnY, btnW, btnH)
    love.graphics.setColor(hovered and colors.buttonHover or colors.button)
    love.graphics.rectangle("fill", ox, btnY, btnW, btnH, 8, 8)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle("line", ox, btnY, btnW, btnH, 8, 8)
    love.graphics.setColor(colors.text)
    love.graphics.printf(opt.label, ox, btnY + 12, btnW, "center")

    opt._bounds = { x = ox, y = btnY, w = btnW, h = btnH }
  end
end

local function handlePauseMenuClick(x, y)
  if not uiState.isPaused then return false end
  for _, opt in ipairs(pauseMenu.options) do
    local b = opt._bounds
    if b and isPointInRect(x, y, b.x, b.y, b.w, b.h) then
      if opt.key == "resume" then
        uiState.isPaused = false
      elseif opt.key == "restart" then
        restartGame()
      elseif opt.key == "quit" then
        love.event.quit()
      end
      return true
    end
  end
  return true
end

local function distanceSqTiles(ax, ay, bx, by)
  local dx = ax - bx
  local dy = ay - by
  return dx * dx + dy * dy
end

local function acquireTreeTargetForLumberyard(b)
  local def = buildingDefs.lumberyard
  local bestIndex = nil
  local bestDistSq = math.huge
  for index, t in ipairs(trees) do
    if t.alive then
      local distSq = distanceSqTiles(b.tileX, b.tileY, t.tileX, t.tileY)
      if distSq <= (def.radiusTiles * def.radiusTiles) and distSq < bestDistSq then
        bestDistSq = distSq
        bestIndex = index
      end
    end
  end
  b.chopTargetIndex = bestIndex
end

local function updateLumberyards(dt)
  for _, b in ipairs(buildings) do
    if b.type == "lumberyard" then
      local def = buildingDefs.lumberyard
      if not b.chopTargetIndex then
        acquireTreeTargetForLumberyard(b)
      end

      if b.chopTargetIndex then
        local t = trees[b.chopTargetIndex]
        -- Validate target
        if not t or not t.alive then
          b.chopTargetIndex = nil
        else
          local distSq = distanceSqTiles(b.tileX, b.tileY, t.tileX, t.tileY)
          if distSq > (def.radiusTiles * def.radiusTiles) then
            b.chopTargetIndex = nil
          else
            -- Chop
            t.health = t.health - def.chopRate * dt
            if t.health <= 0 then
              t.alive = false
              gameState.resources.wood = (gameState.resources.wood or 0) + def.woodPerTree
              b.chopTargetIndex = nil
            end
          end
        end
      end
    end
  end
end

local function generateTrees()
  trees = {}
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
        table.insert(trees, { tileX = tx, tileY = ty, alive = true, health = 3.0 })
      end
    end
  end
end

function love.load()
  love.window.setTitle("City Builder - Prototype")
  love.graphics.setBackgroundColor(colors.background)

  local optionHeight, spacing, padding = 48, 8, 12
  local count = #buildMenu.options
  buildMenu.height = padding + (optionHeight * count) + (spacing * math.max(0, count - 1)) + padding

  math.randomseed(os.time())

  local screenW, screenH = love.graphics.getDimensions()
  local baseTilesX = math.floor(screenW / TILE_SIZE)
  local baseTilesY = math.floor(screenH / TILE_SIZE)
  world.tilesX = math.max(32, baseTilesX * 4)
  world.tilesY = math.max(32, baseTilesY * 4)

  generateTrees()
end

function love.update(dt)
  if uiState.isPaused then return end

  local totals = getTotalProductionPerSecond()
  gameState.productionRates = totals
  for resourceName, rate in pairs(totals) do
    local current = gameState.resources[resourceName] or 0
    gameState.resources[resourceName] = current + rate * dt
  end

  updateLumberyards(dt)

  local mx, my = love.mouse.getPosition()
  local screenW, screenH = love.graphics.getDimensions()
  local margin = 24
  local dx, dy = 0, 0
  if mx <= margin then dx = -1 end
  if mx >= screenW - margin then dx = 1 end
  if my <= margin then dy = -1 end
  if my >= screenH - margin then dy = 1 end

  camera.x = camera.x + dx * camera.panSpeed * dt
  camera.y = camera.y + dy * camera.panSpeed * dt

  local maxCamX = math.max(0, world.tilesX * TILE_SIZE - screenW)
  local maxCamY = math.max(0, world.tilesY * TILE_SIZE - screenH)
  if camera.x < 0 then camera.x = 0 end
  if camera.y < 0 then camera.y = 0 end
  if camera.x > maxCamX then camera.x = maxCamX end
  if camera.y > maxCamY then camera.y = maxCamY end
end

function love.draw()
  love.graphics.push()
  love.graphics.translate(-camera.x, -camera.y)

  drawGrid()
  drawLumberyardRadii()
  drawTrees()
  drawBuildings()
  drawPlacementPreview()

  love.graphics.pop()

  drawButton(buildButton)
  if uiState.isBuildMenuOpen then
    drawBuildMenu()
  end
  drawHUD()

  if not uiState.isPaused then
    love.graphics.setColor(colors.text)
    local hintY = love.graphics.getHeight() - 24
    love.graphics.print("Click 'Build' -> choose 'House' or 'Lumberyard' -> place on the map. Move mouse to screen edges to pan. Right click to cancel placement.", 16, hintY)
  end

  drawPauseMenu()
end

function love.mousepressed(x, y, button)
  if uiState.isPaused then
    if button == 1 then
      handlePauseMenuClick(x, y)
    end
    return
  end

  if button == 2 then
    if uiState.isPlacingBuilding then
      uiState.isPlacingBuilding = false
      uiState.selectedBuildingType = nil
      return
    elseif uiState.isBuildMenuOpen then
      uiState.isBuildMenuOpen = false
      return
    end
  end

  if button ~= 1 then return end

  if isPointInRect(x, y, buildButton.x, buildButton.y, buildButton.width, buildButton.height) then
    uiState.isBuildMenuOpen = not uiState.isBuildMenuOpen
    return
  end

  if uiState.isBuildMenuOpen then
    local option = getMenuOptionAt(x, y)
    if option then
      uiState.selectedBuildingType = option.key
      uiState.isPlacingBuilding = true
      uiState.isBuildMenuOpen = false
      return
    else
      uiState.isBuildMenuOpen = false
    end
  end

  if uiState.isPlacingBuilding and uiState.selectedBuildingType then
    local tileX, tileY = getMouseTile()
    if not isOverUI(x, y) and canPlaceAt(tileX, tileY) and canAfford(uiState.selectedBuildingType) then
      payCost(uiState.selectedBuildingType)
      placeBuilding(uiState.selectedBuildingType, tileX, tileY)
      uiState.isPlacingBuilding = false
      uiState.selectedBuildingType = nil
      return
    end
  end
end

function love.keypressed(key)
  if key == "escape" then
    uiState.isPaused = not uiState.isPaused
    return
  end
end

function love.mousereleased(x, y, button)
end 