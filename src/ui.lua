-- ui.lua
-- UI elements: build button, build menu, HUD, pause menu

local constants = require('src.constants')
local utils = require('src.utils')
local colors = constants.colors

local ui = {}

ui.buildButton = { x = 16, y = 16, width = 120, height = 40, label = "Build" }

ui.buildMenu = {
  x = 16, -- not used for drawing when centered, kept for compatibility
  y = 72, -- not used for drawing when centered, kept for compatibility
  width = 220,
  height = 120,
  optionHeight = 48,
  options = {
    { key = "house", label = "House", color = { 0.9, 0.6, 0.2, 1.0 } },
    { key = "lumberyard", label = "Lumberyard", color = { 0.3, 0.7, 0.3, 1.0 } }
  }
}

ui.pauseMenu = {
  width = 360,
  optionHeight = 48,
  optionSpacing = 10,
  options = {
    { key = "resume", label = "Resume" },
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

function ui.drawBuildButton()
  local b = ui.buildButton
  local mx, my = love.mouse.getPosition()
  local hovered = utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
  love.graphics.setColor(hovered and colors.buttonHover or colors.button)
  love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 6, 6)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", b.x, b.y, b.width, b.height, 6, 6)
  love.graphics.setColor(colors.text)
  love.graphics.printf(b.label, b.x, b.y + 12, b.width, "center")
end

function ui.drawBuildMenu(state, buildingDefs)
  if not state.ui.isBuildMenuOpen and state.ui.buildMenuAlpha <= 0 then return end
  ui.computeBuildMenuSize(buildingDefs)

  -- Animate alpha towards target (open -> 1, closed -> 0)
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
  end

  love.graphics.pop()
end

function ui.drawHUD(state)
  local x = ui.buildButton.x + ui.buildButton.width + 16
  local y = 16
  local w = 320
  local h = 84
  love.graphics.setColor(colors.uiPanel)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)

  love.graphics.setColor(colors.text)
  local wood = math.floor(state.game.resources.wood + 0.5)
  local woodRate = state.game.productionRates.wood or 0
  love.graphics.print(string.format("Wood: %d  (+%.1f/s passive)", wood, woodRate), x + 12, y + 12)

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
end

return ui 