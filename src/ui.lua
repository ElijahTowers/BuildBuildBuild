-- ui.lua
-- UI elements: build button, build menu, HUD, pause menu

local constants = require('src.constants')
local utils = require('src.utils')
local colors = constants.colors

local ui = {}

ui.buildButton = { x = 16, y = 16, width = 120, height = 40, label = "Build" }
ui.roadButton = { x = 16 + 120 + 8, y = 16, width = 120, height = 40, label = "Roads" }
ui.villagersButton = { x = 16 + (120 + 8) * 2, y = 16, width = 140, height = 40, label = "Villagers" }

ui.buildMenu = {
  x = 16, -- not used for drawing when centered, kept for compatibility
  y = 72, -- not used for drawing when centered, kept for compatibility
  width = 220,
  height = 120,
  optionHeight = 48,
  options = {
    { key = "house", label = "House", color = { 0.9, 0.6, 0.2, 1.0 } },
    { key = "lumberyard", label = "Lumberyard", color = { 0.3, 0.7, 0.3, 1.0 } },
    { key = "warehouse", label = "Warehouse", color = { 0.6, 0.6, 0.7, 1.0 } },
    { key = "builder", label = "Builders Workplace", color = { 0.7, 0.5, 0.3, 1.0 } }
  }
}

ui.pauseMenu = {
  width = 360,
  optionHeight = 48,
  optionSpacing = 10,
  options = {
    { key = "resume", label = "Resume" },
    { key = "save", label = "Save (F5 / Ctrl+S)" },
    { key = "load", label = "Load (F9 / Ctrl+L)" },
    { key = "restart", label = "Restart" },
    { key = "quit", label = "Quit" }
  }
}

function ui.computeBuildMenuHeight()
  local padding, spacing = 12, 8
  local count = #ui.buildMenu.options
  ui.buildMenu.height = padding + (ui.buildMenu.optionHeight * count) + (spacing * math.max(0, count - 1)) + padding
end

-- Dynamically compute a width that fits the widest option text
function ui.computeBuildMenuSize(buildingDefs)
  local minWidth = 320
  local paddingLeftToText = 12 + 52 -- left panel padding + icon area
  local paddingRight = 12
  local maxTextW = 0
  for _, option in ipairs(ui.buildMenu.options) do
    local def = buildingDefs[option.key]
    local costText = ""
    if def and def.cost and def.cost.wood then
      costText = string.format(" (Cost: %d wood)", def.cost.wood)
    end
    local text = option.label .. costText
    local textW = love.graphics.getFont():getWidth(text)
    if textW > maxTextW then maxTextW = textW end
  end
  ui.buildMenu.width = math.max(minWidth, paddingLeftToText + maxTextW + paddingRight)
end

-- Returns centered rect for the build menu
function ui.getBuildMenuRect()
  local m = ui.buildMenu
  local screenW, screenH = love.graphics.getDimensions()
  local x = (screenW - m.width) / 2
  local y = (screenH - m.height) / 2
  return x, y, m.width, m.height
end

function ui.isOverBuildButton(mx, my)
  local b = ui.buildButton
  return utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
end

function ui.isOverRoadButton(mx, my)
  local b = ui.roadButton
  return utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
end

function ui.isOverVillagersButton(mx, my)
  local b = ui.villagersButton
  return utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
end

function ui.isOverBuildMenu(mx, my)
  local x, y, w, h = ui.getBuildMenuRect()
  return utils.isPointInRect(mx, my, x, y, w, h)
end

function ui.getBuildMenuOptionAt(mx, my)
  local m = ui.buildMenu
  local optionHeight = m.optionHeight
  local x, y, w, h = ui.getBuildMenuRect()
  for index, option in ipairs(m.options) do
    local ox = x + 12
    local oy = y + 12 + (index - 1) * (optionHeight + 8)
    local ow = w - 24
    local oh = optionHeight
    if utils.isPointInRect(mx, my, ox, oy, ow, oh) then
      return option
    end
  end
  return nil
end

function ui.drawTopButtons(state)
  local function drawButton(b, active, hint)
    local mx, my = love.mouse.getPosition()
    local hovered = utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
    love.graphics.setColor(active and colors.buttonHover or (hovered and colors.buttonHover or colors.button))
    love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 6, 6)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle("line", b.x, b.y, b.width, b.height, 6, 6)
    love.graphics.setColor(colors.text)
    love.graphics.printf(b.label, b.x, b.y + 12, b.width, "center")
    if hint then
      love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], 0.6)
      love.graphics.printf(hint, b.x + b.width - 28, b.y + 6, 24, "right")
    end
  end

  drawButton(ui.buildButton, false, "C")
  drawButton(ui.roadButton, state.ui.isPlacingRoad, "R")
  drawButton(ui.villagersButton, state.ui.isVillagersPanelOpen, "V")
end

function ui.drawBuildMenu(state, buildingDefs)
  if not state.ui.isBuildMenuOpen and state.ui.buildMenuAlpha <= 0 then return end
  ui.computeBuildMenuSize(buildingDefs)
  ui.computeBuildMenuHeight()
  local target = state.ui.isBuildMenuOpen and 1 or 0
  state.ui.buildMenuAlpha = state.ui.buildMenuAlpha + (target - state.ui.buildMenuAlpha) * 0.2
  local a = state.ui.buildMenuAlpha
  if a < 0.01 then return end

  local m = ui.buildMenu
  local x, y, w, h = ui.getBuildMenuRect()

  love.graphics.setColor(0, 0, 0, 0.2 * a)
  love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

  local scale = 0.95 + 0.05 * a
  love.graphics.push()
  love.graphics.translate(x + w / 2, y + h / 2)
  love.graphics.scale(scale, scale)
  love.graphics.translate(-(x + w / 2), -(y + h / 2))

  love.graphics.setColor(colors.uiPanel[1], colors.uiPanel[2], colors.uiPanel[3], (colors.uiPanel[4] or 1) * a)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(colors.uiPanelOutline[1], colors.uiPanelOutline[2], colors.uiPanelOutline[3], (colors.uiPanelOutline[4] or 1) * a)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)

  local optionHeight = m.optionHeight
  for index, option in ipairs(m.options) do
    local ox = x + 12
    local oy = y + 12 + (index - 1) * (optionHeight + 8)
    local ow = w - 24
    local oh = optionHeight
    local mx, my = love.mouse.getPosition()
    local hovered = utils.isPointInRect(mx, my, ox, oy, ow, oh)

    love.graphics.setColor(hovered and colors.buttonHover or colors.button)
    love.graphics.rectangle("fill", ox, oy, ow, oh, 6, 6)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle("line", ox, oy, ow, oh, 6, 6)

    love.graphics.setColor(option.color)
    love.graphics.rectangle("fill", ox + 10, oy + 8, 32, 32, 4, 4)

    love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], (colors.text[4] or 1) * a)
    local def = buildingDefs[option.key]
    local costText = ""
    if def and def.cost and def.cost.wood then
      costText = string.format(" (Cost: %d wood)", def.cost.wood)
    end
    love.graphics.print(option.label .. costText, ox + 52, oy + 12)

    -- shortcuts for quick build (if defined)
    local shortcut = (option.key == 'house' and 'H') or (option.key == 'lumberyard' and 'L') or (option.key == 'warehouse' and 'W') or (option.key == 'builder' and 'B') or nil
    if shortcut then
      love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], 0.6)
      love.graphics.printf(shortcut, ox + ow - 28, oy + 6, 24, 'right')
    end
  end

  love.graphics.pop()
end

function ui.drawVillagersPanel(state)
  if not state.ui.isVillagersPanelOpen then return end
  -- Backdrop shade to indicate pause
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

  local w, h = 520, 200
  local screenW, screenH = love.graphics.getDimensions()
  local x = (screenW - w) / 2
  local y = (screenH - h) / 2
  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle('fill', x, y, w, h, 10, 10)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle('line', x, y, w, h, 10, 10)

  love.graphics.setColor(colors.text)
  local pop = state.game.population
  love.graphics.print(string.format('Villagers: %d / %d assigned', pop.assigned or 0, pop.total or 0), x + 12, y + 12)
  love.graphics.print(string.format('Capacity: %d', pop.capacity or 0), x + 12, y + 32)

  local btns = {}
  local rowY = y + 64
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'lumberyard' or b.type == 'builder' then
      local name = (b.type == 'lumberyard') and 'Lumberyard' or 'Builders Workplace'
      local maxSlots = (b.type == 'lumberyard') and (state.buildingDefs.lumberyard.numWorkers or 0) or (state.buildingDefs.builder.numWorkers or 0)
      love.graphics.setColor(colors.text)
      love.graphics.print(string.format('%s (%d/%d)', name, b.assigned or 0, maxSlots), x + 12, rowY)
      local btnW, btnH = 28, 24
      local remX, remY = x + w - 76, rowY - 4
      local addX, addY = x + w - 40, rowY - 4
      love.graphics.setColor(colors.button)
      love.graphics.rectangle('fill', remX, remY, btnW, btnH, 6, 6)
      love.graphics.setColor(colors.uiPanelOutline)
      love.graphics.rectangle('line', remX, remY, btnW, btnH, 6, 6)
      love.graphics.setColor(colors.text)
      love.graphics.printf('-', remX, remY + 4, btnW, 'center')
      love.graphics.setColor(colors.button)
      love.graphics.rectangle('fill', addX, addY, btnW, btnH, 6, 6)
      love.graphics.setColor(colors.uiPanelOutline)
      love.graphics.rectangle('line', addX, addY, btnW, btnH, 6, 6)
      love.graphics.setColor(colors.text)
      love.graphics.printf('+', addX, addY + 4, btnW, 'center')
      table.insert(btns, { type = b.type, b = b, add = { x = addX, y = addY, w = btnW, h = btnH }, rem = { x = remX, y = remY, w = btnW, h = btnH } })
      rowY = rowY + 28
    end
  end
  state.ui._villagersPanelButtons = btns
end

-- Minimap (top-right). Shows roads, trees, buildings, and camera viewport.
function ui.drawMiniMap(state)
  local TILE = constants.TILE_SIZE
  local world = state.world
  if world.tilesX <= 0 or world.tilesY <= 0 then return end

  local padding = 16
  local screenW, screenH = love.graphics.getDimensions()
  local desiredW = 180
  local scale = desiredW / world.tilesX
  local mapW = desiredW
  local mapH = world.tilesY * scale

  -- Place at top-right; if villagers panel open, place below it
  local yOffset = 16
  if state.ui.isVillagersPanelOpen then
    yOffset = yOffset + 140 + 8 -- villagers panel height + gap
  end
  local x = screenW - padding - mapW
  local y = yOffset

  -- Store for click handling
  state.ui._miniMap = { x = x, y = y, w = mapW, h = mapH, scale = scale }

  -- Background panel
  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle('fill', x - 8, y - 8, mapW + 16, mapH + 16, 8, 8)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle('line', x - 8, y - 8, mapW + 16, mapH + 16, 8, 8)

  -- Draw roads
  if state.game.roads then
    love.graphics.setColor(0.5, 0.5, 0.52, 0.9)
    for _, rd in pairs(state.game.roads) do
      local rx = x + rd.tileX * scale
      local ry = y + rd.tileY * scale
      love.graphics.rectangle('fill', rx, ry, scale, scale)
    end
  end

  -- Draw trees
  love.graphics.setColor(colors.treeFill)
  for _, t in ipairs(state.game.trees) do
    if t.alive then
      local tx = x + t.tileX * scale
      local ty = y + t.tileY * scale
      love.graphics.rectangle('fill', tx + scale * 0.25, ty + scale * 0.25, math.max(1, scale * 0.5), math.max(1, scale * 0.5))
    end
  end

  -- Draw buildings
  for _, b in ipairs(state.game.buildings) do
    local bx = x + b.tileX * scale
    local by = y + b.tileY * scale
    love.graphics.setColor(b.color[1], b.color[2], b.color[3], 1)
    love.graphics.rectangle('fill', bx, by, scale, scale)
    love.graphics.setColor(colors.outline)
    love.graphics.rectangle('line', bx, by, scale, scale)
  end

  -- Draw villagers
  if state.game.villagers then
    love.graphics.setColor(colors.worker)
    for _, v in ipairs(state.game.villagers) do
      local vx = x + (v.x / TILE) * scale
      local vy = y + (v.y / TILE) * scale
      love.graphics.rectangle('fill', vx - 1, vy - 1, 2, 2)
    end
  end

  -- Camera viewport rectangle
  local camTileX = state.camera.x / TILE
  local camTileY = state.camera.y / TILE
  local viewTilesW = (screenW / state.camera.scale) / TILE
  local viewTilesH = (screenH / state.camera.scale) / TILE
  local vx = x + camTileX * scale
  local vy = y + camTileY * scale
  local vw = viewTilesW * scale
  local vh = viewTilesH * scale
  love.graphics.setColor(1, 1, 1, 0.8)
  love.graphics.rectangle('line', vx, vy, vw, vh)
end

function ui.drawHUD(state)
  local x = ui.villagersButton.x + ui.villagersButton.width + 16
  local y = 16
  local w = 600
  local h = 84
  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)

  love.graphics.setColor(colors.text)
  local baseWood = math.floor(state.game.resources.wood + 0.5)
  local storedWood = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      storedWood = storedWood + b.storage.wood
    end
  end
  local totalWood = baseWood + storedWood
  love.graphics.print(string.format("Wood: %d", totalWood), x + 12, y + 12)

  local hours = math.floor(state.time.normalized * 24) % 24
  local minutes = math.floor((state.time.normalized * 24 - hours) * 60)
  local tnorm = state.time.normalized
  local isDay = (tnorm >= 0.25 and tnorm < 0.75)
  love.graphics.print(string.format("Time: %02d:%02d (%s)", hours, minutes, isDay and "Day" or "Night"), x + 220, y + 12)
  love.graphics.print(string.format("Speed: %dx", state.time.speed or 1), x + 400, y + 12)

  local btnW, btnH = 36, 22
  local s1x = x + 390; local s1y = y + 36
  local s2x = s1x + btnW + 6; local s2y = s1y
  local s4x = s2x + btnW + 6; local s4y = s1y
  local s8x = s4x + btnW + 6; local s8y = s1y
  local function drawSpeed(xb, yb, label, active)
    love.graphics.setColor(active and colors.buttonHover or colors.button)
    love.graphics.rectangle('fill', xb, yb, btnW, btnH, 6, 6)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle('line', xb, yb, btnW, btnH, 6, 6)
    love.graphics.setColor(colors.text)
    love.graphics.printf(label, xb, yb + 4, btnW, 'center')
  end
  drawSpeed(s1x, s1y, '1x', (state.time.speed or 1) == 1)
  drawSpeed(s2x, s2y, '2x', (state.time.speed or 1) == 2)
  drawSpeed(s4x, s4y, '4x', (state.time.speed or 1) == 4)
  drawSpeed(s8x, s8y, '8x', (state.time.speed or 1) == 8)
  state.ui._speedButtons = {
    s1 = { x = s1x, y = s1y, w = btnW, h = btnH, v = 1 },
    s2 = { x = s2x, y = s2y, w = btnW, h = btnH, v = 2 },
    s4 = { x = s4x, y = s4y, w = btnW, h = btnH, v = 4 },
    s8 = { x = s8x, y = s8y, w = btnW, h = btnH, v = 8 }
  }

  if state.ui.isPlacingBuilding and state.ui.selectedBuildingType and not state.ui.isPaused then
    local def = state.buildingDefs[state.ui.selectedBuildingType]
    if def and def.cost and def.cost.wood then
      local costStr = string.format("Cost: %d wood", def.cost.wood)
      love.graphics.setColor(colors.text)
      love.graphics.print(costStr, x + 12, y + 30)
    end
    if state.ui.selectedBuildingType == "lumberyard" then
      love.graphics.setColor(colors.text)
      love.graphics.print(string.format("Radius: %d tiles, Workers: %d", state.buildingDefs.lumberyard.radiusTiles, state.buildingDefs.lumberyard.numWorkers), x + 12, y + 48)
    end
  end

  if state.ui.isPlacingRoad then
    love.graphics.setColor(colors.text)
    local costPer = state.buildingDefs.road.costPerTile.wood or 0
    love.graphics.print(string.format("Road: click-drag to build, cost %d wood/tile. Right click to cancel.", costPer), x + 12, y + 30)
  end

  ui.drawVillagersPanel(state)
end

function ui.drawPrompt(state)
  if not state.ui.promptText then return end
  local t = state.ui.promptT or 0
  local dur = state.ui.promptDuration or 0
  local sticky = state.ui.promptSticky
  if (not sticky) and dur > 0 and t > dur then return end

  local alpha = 1.0
  if (not sticky) and dur > 0 and dur < 9000 then
    local remain = math.max(0, dur - t)
    alpha = math.min(1, remain / (dur * 0.5))
  end

  local msg = state.ui.promptText
  local screenW, screenH = love.graphics.getDimensions()
  -- Place below the top buttons and HUD, left side
  local x = 16
  local y = 16 + 40 + 8 + 84 + 8 -- top buttons height + spacing + HUD height + spacing
  local w = math.min(520, screenW - x - 16)
  local h = 56

  love.graphics.setColor(0, 0, 0, 0.75 * alpha)
  love.graphics.rectangle('fill', x, y, w, h, 10, 10)
  love.graphics.setColor(colors.uiPanelOutline[1], colors.uiPanelOutline[2], colors.uiPanelOutline[3], 0.9 * alpha)
  love.graphics.rectangle('line', x, y, w, h, 10, 10)

  love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], alpha)
  love.graphics.printf(msg, x + 12, y + 16, w - 24, 'left')
end

function ui.drawPauseMenu(state)
  if not state.ui.isPaused then return end
  local screenW, screenH = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)

  local contentHeight = #ui.pauseMenu.options * ui.pauseMenu.optionHeight + (#ui.pauseMenu.options - 1) * ui.pauseMenu.optionSpacing
  local panelW = ui.pauseMenu.width
  local panelH = contentHeight + 40
  local panelX = (screenW - panelW) / 2
  local panelY = (screenH - panelH) / 2

  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 10, 10)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 10, 10)

  local ox = panelX + 20
  local oy = panelY + 20
  for i, opt in ipairs(ui.pauseMenu.options) do
    local btnY = oy + (i - 1) * (ui.pauseMenu.optionHeight + ui.pauseMenu.optionSpacing)
    local btnW = panelW - 40
    local btnH = ui.pauseMenu.optionHeight
    local mx, my = love.mouse.getPosition()
    local hovered = utils.isPointInRect(mx, my, ox, btnY, btnW, btnH)
    love.graphics.setColor(hovered and colors.buttonHover or colors.button)
    love.graphics.rectangle("fill", ox, btnY, btnW, btnH, 8, 8)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle("line", ox, btnY, btnW, btnH, 8, 8)
    love.graphics.setColor(colors.text)
    love.graphics.printf(opt.label, ox, btnY + 12, btnW, "center")
    opt._bounds = { x = ox, y = btnY, w = btnW, h = btnH }
  end

  -- Save/Load slot dialog overlay
  if state.ui._saveLoadMode then
    local title = state.ui._saveLoadMode == 'save' and 'Select save slot' or 'Select load slot'
    local w, h = 360, 240
    local x = (screenW - w) / 2
    local y = (screenH - h) / 2
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
    love.graphics.setColor(colors.uiPanel)
    love.graphics.rectangle('fill', x, y, w, h, 10, 10)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle('line', x, y, w, h, 10, 10)
    love.graphics.setColor(colors.text)
    love.graphics.printf(title, x, y + 14, w, 'center')

    local btns = {}
    local btnW, btnH = w - 40, 40
    local bx = x + 20
    local by = y + 60
    for slot = 1, 3 do
      local exists = love.filesystem.getInfo(string.format('save_%d.json', slot)) ~= nil
      local mx, my = love.mouse.getPosition()
      local hovered = utils.isPointInRect(mx, my, bx, by, btnW, btnH)
      love.graphics.setColor(hovered and colors.buttonHover or colors.button)
      love.graphics.rectangle('fill', bx, by, btnW, btnH, 8, 8)
      love.graphics.setColor(colors.uiPanelOutline)
      love.graphics.rectangle('line', bx, by, btnW, btnH, 8, 8)
      love.graphics.setColor(colors.text)
      local label = exists and string.format('Slot %d  (occupied)', slot) or string.format('Slot %d  (empty)', slot)
      love.graphics.printf(label, bx, by + 10, btnW, 'center')
      table.insert(btns, { x = bx, y = by, w = btnW, h = btnH, slot = slot })
      by = by + btnH + 10
    end
    -- Cancel button
    local hovered = utils.isPointInRect(love.mouse.getX(), love.mouse.getY(), bx, y + h - 20 - btnH, btnW, btnH)
    love.graphics.setColor(hovered and colors.buttonHover or colors.button)
    love.graphics.rectangle('fill', bx, y + h - 20 - btnH, btnW, btnH, 8, 8)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle('line', bx, y + h - 20 - btnH, btnW, btnH, 8, 8)
    love.graphics.setColor(colors.text)
    love.graphics.printf('Cancel', bx, y + h - 20 - btnH + 10, btnW, 'center')
    table.insert(btns, { x = bx, y = y + h - 20 - btnH, w = btnW, h = btnH, cancel = true })

    state.ui._saveLoadButtons = btns
  else
    state.ui._saveLoadButtons = nil
  end
end

return ui 