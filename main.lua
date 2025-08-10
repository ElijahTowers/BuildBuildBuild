local TILE_SIZE = 32

local uiState = {
  isBuildMenuOpen = false,
  isPlacingBuilding = false,
  selectedBuildingType = nil
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
  outline = { 1.0, 1.0, 1.0, 0.3 }
}

local buildings = {}

local function isPointInRect(px, py, rx, ry, rw, rh)
  return px >= rx and px <= (rx + rw) and py >= ry and py <= (ry + rh)
end

local function getMouseTile()
  local mx, my = love.mouse.getX(), love.mouse.getY()
  local tileX = math.floor(mx / TILE_SIZE)
  local tileY = math.floor(my / TILE_SIZE)
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

local function canPlaceAt(tileX, tileY)
  for _, b in ipairs(buildings) do
    if b.tileX == tileX and b.tileY == tileY then
      return false
    end
  end
  return true
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

  table.insert(buildings, {
    type = selectedType,
    tileX = tileX,
    tileY = tileY,
    color = color
  })
end

local function drawGrid()
  local width, height = love.graphics.getDimensions()
  love.graphics.setColor(colors.grid)
  for x = 0, width, TILE_SIZE do
    love.graphics.line(x, 0, x, height)
  end
  for y = 0, height, TILE_SIZE do
    love.graphics.line(0, y, width, y)
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
    love.graphics.print(option.label, ox + 52, oy + 12)
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
  if not uiState.isPlacingBuilding or not uiState.selectedBuildingType then
    return
  end

  local tileX, tileY = getMouseTile()
  local px = tileX * TILE_SIZE
  local py = tileY * TILE_SIZE

  local isValid = canPlaceAt(tileX, tileY) and not isOverUI(love.mouse.getX(), love.mouse.getY())

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

function love.load()
  love.window.setTitle("City Builder - Prototype")
  love.graphics.setBackgroundColor(colors.background)

  local optionHeight, spacing, padding = 48, 8, 12
  local count = #buildMenu.options
  buildMenu.height = padding + (optionHeight * count) + (spacing * math.max(0, count - 1)) + padding
end

function love.update(dt)
  -- No continuous update logic needed yet
end

function love.draw()
  drawGrid()
  drawBuildings()
  drawPlacementPreview()

  drawButton(buildButton)
  if uiState.isBuildMenuOpen then
    drawBuildMenu()
  end

  love.graphics.setColor(colors.text)
  local hintY = love.graphics.getHeight() - 24
  love.graphics.print("Click 'Build' -> choose 'House' or 'Lumberyard' -> click on the map to place. Right click/ESC to cancel.", 16, hintY)
end

function love.mousepressed(x, y, button)
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
    if not isOverUI(x, y) and canPlaceAt(tileX, tileY) then
      placeBuilding(uiState.selectedBuildingType, tileX, tileY)
      uiState.isPlacingBuilding = false
      uiState.selectedBuildingType = nil
      return
    end
  end
end

function love.keypressed(key)
  if key == "escape" then
    if uiState.isPlacingBuilding then
      uiState.isPlacingBuilding = false
      uiState.selectedBuildingType = nil
    elseif uiState.isBuildMenuOpen then
      uiState.isBuildMenuOpen = false
    end
  end
end

function love.mousereleased(x, y, button)
  -- Reserved for future use
end 