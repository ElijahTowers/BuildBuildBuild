-- ui.lua
-- UI elements: build button, build menu, HUD, pause menu

local constants = require('src.constants')
local state = require('src.state')
local utils = require('src.utils')
local colors = constants.colors
local buildings = require('src.buildings')

local ui = {}

-- Pointer helper: returns virtual cursor if enabled (handheld), else mouse
function ui.getPointer()
  if state.ui and state.ui._handheldMode and state.ui._useVirtualCursor and state.ui._virtualCursor then
    return state.ui._virtualCursor.x or 0, state.ui._virtualCursor.y or 0
  end
  return love.mouse.getPosition()
end

-- Small-screen helpers for handhelds
local function isSmallScreen()
  local w, h = love.graphics.getDimensions()
  return (state.ui and (state.ui._forceSmallScreen or state.ui._handheldMode)) or (w < 1000) or (h < 600)
end

local function pushUIFont()
  ui._fontStack = ui._fontStack or {}
  table.insert(ui._fontStack, love.graphics.getFont())
  if isSmallScreen() then
    ui._smallFont = ui._smallFont or love.graphics.newFont(18)
    love.graphics.setFont(ui._smallFont)
  end
end

local function pushTinyFont()
  ui._fontStack = ui._fontStack or {}
  table.insert(ui._fontStack, love.graphics.getFont())
  ui._tinyFont = ui._tinyFont or love.graphics.newFont(12)
  love.graphics.setFont(ui._tinyFont)
end

local function popUIFont()
  ui._fontStack = ui._fontStack or {}
  local n = #ui._fontStack
  if n > 0 then
    local f = ui._fontStack[n]
    ui._fontStack[n] = nil
    love.graphics.setFont(f)
  end
end

-- Truncate text to a maximum pixel width using the current font
local function truncateToWidth(text, maxWidth)
  local font = love.graphics.getFont()
  if font:getWidth(text) <= maxWidth then return text end
  local ell = '…'
  local ellW = font:getWidth(ell)
  local s = text
  while #s > 0 and font:getWidth(s) + ellW > maxWidth do
    s = s:sub(1, #s - 1)
  end
  if #s == 0 then return ell end
  return s .. ell
end

ui.buildButton = { x = 16, y = 16, width = 120, height = 40, label = "Build" }
ui.roadButton = { x = 16 + 120 + 8, y = 16, width = 120, height = 40, label = "Roads" }
ui.villagersButton = { x = 16 + (120 + 8) * 2, y = 16, width = 140, height = 40, label = "Villagers" }
-- Move queue button under the build button
ui.queueButton = {
  x = ui.buildButton.x,
  y = ui.buildButton.y + ui.buildButton.height + 8,
  width = ui.buildButton.width,
  height = ui.buildButton.height,
  label = "Build Queue"
}


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
    { key = "market", label = "Market", color = { 0.85, 0.5, 0.25, 1.0 } },
    { key = "builder", label = "Builders Workplace", color = { 0.7, 0.5, 0.3, 1.0 } },
    { key = "farm", label = "Farm", color = { 0.7, 0.8, 0.3, 1.0 } },
    { key = "research", label = "Research Center", color = { 0.5, 0.6, 0.9, 1.0 } },
    { key = "flowerbed", label = "Flower Bed (Decor)", color = { 0.95, 0.65, 0.75, 1.0 } },
    { key = "road", label = "Roads", color = { 0.2, 0.2, 0.22, 1.0 } }
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

function ui.isOverQueueButton(mx, my)
  local b = ui.queueButton
  return utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
end



function ui.isOverBuildMenu(mx, my)
  local x, y, w, h = ui.getBuildMenuRect()
  return utils.isPointInRect(mx, my, x, y, w, h)
end

function ui.getBuildMenuOptionAt(mx, my)
  if state.ui._handheldMode and state.ui._buildMenuBounds then
    for _, option in ipairs(state.ui._buildMenuBounds) do
      local b = option._bounds
      if b and utils.isPointInRect(mx, my, b.x, b.y, b.w, b.h) then
        return option
      end
    end
    return nil
  end
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
  if state.ui._handheldMode then return end
  -- Fancy skin helpers
  local function drawFancyPanel(x, y, w, h)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle('fill', x + 2, y + 3, w, h, 8, 8)
    love.graphics.setColor(0.16, 0.23, 0.16, 0.96)
    love.graphics.rectangle('fill', x, y, w, h, 8, 8)
    -- soft highlight
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.rectangle('fill', x + 4, y + 4, w - 8, math.max(10, h * 0.35), 6, 6)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle('line', x, y, w, h, 8, 8)
  end

  local function drawButton(b, active, hint)
    local mx, my = ui.getPointer()
    local hovered = utils.isPointInRect(mx, my, b.x, b.y, b.width, b.height)
    -- parchment-style button
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.rectangle('fill', b.x - 2, b.y + 2, b.width + 4, b.height + 4, 6, 6)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', b.x, b.y, b.width, b.height, 6, 6)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle('line', b.x, b.y, b.width, b.height, 6, 6)
    if active or hovered then
      love.graphics.setColor(0.20, 0.78, 0.30, hovered and 0.18 or 0.12)
      love.graphics.rectangle('fill', b.x + 3, b.y + 3, b.width - 6, b.height - 6, 4, 4)
    end
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf(b.label, b.x, b.y + 12, b.width, "center")
    if hint then
      love.graphics.setColor(0.18, 0.11, 0.06, 0.7)
      love.graphics.printf(hint, b.x + b.width - 28, b.y + 6, 24, "right")
    end
  end

  drawButton(ui.buildButton, false, "C")
  drawButton(ui.roadButton, state.ui.isPlacingRoad, "R")
  drawButton(ui.villagersButton, state.ui.isVillagersPanelOpen, "V")
  drawButton(ui.queueButton, state.ui.isBuildQueueOpen, "Q")
  -- Debug: Mission selector small button to the right of Queue
  local dbg = { x = ui.queueButton.x + ui.queueButton.width + 8, y = ui.queueButton.y, width = 100, height = ui.queueButton.height, label = "Missions" }
  ui._missionSelectorButtons = { open = dbg }
  drawButton(dbg, state.ui.isMissionSelectorOpen, "M")
end

-- Fancy smooth checkmark helper
local function drawFancyCheck(cx, cy, r, pulse)
  r = r or 8
  local a = 0.35 * math.min(1, pulse or 0)
  for i = 1, 3 do
    love.graphics.setColor(1, 0.9, 0.3, a * (1 - (i - 1) * 0.35))
    love.graphics.circle('line', cx, cy, r + i * 3)
  end
  love.graphics.setColor(0.95, 0.85, 0.45, 1.0)
  love.graphics.circle('fill', cx, cy, r)
  love.graphics.setColor(0.55, 0.38, 0.10, 0.95)
  love.graphics.circle('line', cx, cy, r)
  -- glossy highlight
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.ellipse('fill', cx - r * 0.2, cy - r * 0.35, r * 0.6, r * 0.35)
  -- check stroke
  love.graphics.setColor(0.20, 0.78, 0.30, 1.0)
  love.graphics.setLineWidth(3)
  love.graphics.line(cx - r * 0.45, cy + r * 0.05, cx - r * 0.15, cy + r * 0.35)
  love.graphics.line(cx - r * 0.15, cy + r * 0.35, cx + r * 0.50, cy - r * 0.35)
  love.graphics.setLineWidth(1)
end

-- Shared parchment panel helper (matches objectives theme)
local function drawParchmentPanel(px, py, pw, ph)
  -- outer shadow/border (warmer, less bright)
  love.graphics.setColor(0.32, 0.20, 0.10, 1.0)
  love.graphics.rectangle('fill', px - 4, py - 4, pw + 8, ph + 8)
  love.graphics.setColor(0.16, 0.10, 0.05, 1.0)
  love.graphics.rectangle('line', px - 4, py - 4, pw + 8, ph + 8)
  -- parchment body (warmer tone)
  love.graphics.setColor(0.90, 0.76, 0.52, 1.0)
  love.graphics.rectangle('fill', px, py, pw, ph)
  love.graphics.setColor(0.70, 0.48, 0.28, 1.0)
  love.graphics.rectangle('line', px, py, pw, ph)
end

-- Parchment frame only (no inner fill)
local function drawParchmentFrame(px, py, pw, ph)
  love.graphics.setColor(0.32, 0.20, 0.10, 1.0)
  love.graphics.rectangle('line', px - 4, py - 4, pw + 8, ph + 8)
  love.graphics.setColor(0.70, 0.48, 0.28, 1.0)
  love.graphics.rectangle('line', px, py, pw, ph)
end

function ui.drawBuildMenu(state, buildingDefs)
  if not state.ui.isBuildMenuOpen and state.ui.buildMenuAlpha <= 0 then return end
  -- Don't show regular build menu when wheel menu is active in retroid mode
  if state.ui._handheldMode and state.ui._wheelMenuActive then return end
  ui.computeBuildMenuSize(buildingDefs)
  ui.computeBuildMenuHeight()
  local target = state.ui.isBuildMenuOpen and 1 or 0
  state.ui.buildMenuAlpha = state.ui.buildMenuAlpha + (target - state.ui.buildMenuAlpha) * 0.2
  local a = state.ui.buildMenuAlpha
  if a < 0.01 then return end

  local m = ui.buildMenu
  local x, y, w, h = ui.getBuildMenuRect()

  -- Handheld: draw as compact 2-column grid centered near bottom
  if state.ui._handheldMode then
    local screenW, screenH = love.graphics.getDimensions()
    local colW, rowH = 120, 34
    local gap = 8
    local cols = 2
    local opts = m.options
    local count = #opts
    love.graphics.setColor(0, 0, 0, 0.25 * a)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
    local rows = math.ceil(count / cols)
    local totalW = cols * colW + (cols - 1) * gap
    local totalH = rows * rowH + (rows - 1) * gap
    local startX = (screenW - totalW) / 2
    local startY = math.max(40, screenH - totalH - 40)
    -- Use tiny font to ensure labels fit within buttons
    pushTinyFont()
    for i, opt in ipairs(opts) do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local ox = startX + col * (colW + gap)
      local oy = startY + row * (rowH + gap)
      local ow, oh = colW, rowH
      -- panel
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', ox - 2, oy + 2, ow + 4, oh + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', ox, oy, ow, oh, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', ox, oy, ow, oh, 8, 8)
      -- highlight focused item
      if state.ui._buildMenuFocus == i then
        love.graphics.setColor(0.20, 0.78, 0.30, 0.22)
        love.graphics.rectangle('fill', ox + 3, oy + 3, ow - 6, oh - 6, 6, 6)
      end
      -- label
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      local label = truncateToWidth(opt.label, ow - 16)
      love.graphics.printf(label, ox + 8, oy + 8, ow - 16, 'center')
      opt._bounds = { x = ox, y = oy, w = ow, h = oh }
    end
    popUIFont()
    -- store for hit testing
    state.ui._buildMenuBounds = opts
    return
  end

  love.graphics.setColor(0, 0, 0, 0.2 * a)
  love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

  local scale = 0.95 + 0.05 * a
  love.graphics.push()
  love.graphics.translate(x + w / 2, y + h / 2)
  love.graphics.scale(scale, scale)
  love.graphics.translate(-(x + w / 2), -(y + h / 2))

  -- fancy panel skin (objectives panel uses warm brown for contrast)
  love.graphics.setColor(0,0,0,0.25 * a)
  love.graphics.rectangle('fill', x + 3, y + 4, w, h, 10, 10)
  love.graphics.setColor(0.28, 0.20, 0.12, 0.96 * a)
  love.graphics.rectangle('fill', x, y, w, h, 10, 10)
  love.graphics.setColor(1,1,1,0.06 * a)
  love.graphics.rectangle('fill', x + 6, y + 6, w - 12, math.max(16, h * 0.18), 8, 8)
  love.graphics.setColor(colors.uiPanelOutline[1], colors.uiPanelOutline[2], colors.uiPanelOutline[3], (colors.uiPanelOutline[4] or 1) * a)
  love.graphics.rectangle('line', x, y, w, h, 10, 10)

  local optionHeight = m.optionHeight
  if isSmallScreen() then optionHeight = math.max(40, optionHeight - 6) end
  for index, option in ipairs(m.options) do
    local ox = x + 12
    local oy = y + 12 + (index - 1) * (optionHeight + 8)
    local ow = w - 24
    local oh = optionHeight
    local mx, my = ui.getPointer()
    local hovered = utils.isPointInRect(mx, my, ox, oy, ow, oh)
    local focused = (state.ui._buildMenuFocus == index)

    -- parchment-style option row
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.rectangle('fill', ox - 2, oy + 2, ow + 4, oh + 4, 6, 6)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle("fill", ox, oy, ow, oh, 6, 6)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle("line", ox, oy, ow, oh, 6, 6)
    if hovered or focused then
      love.graphics.setColor(0.20, 0.78, 0.30, 0.15)
      love.graphics.rectangle('fill', ox + 3, oy + 3, ow - 6, oh - 6, 4, 4)
    end

    love.graphics.setColor(option.color)
    love.graphics.rectangle("fill", ox + 10, oy + 8, 32, 32, 4, 4)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle("line", ox + 10, oy + 8, 32, 32, 4, 4)
    -- icon inside the square
    love.graphics.push()
    love.graphics.translate(ox + 10 + 16, oy + 8 + 16)
    buildings.drawIcon(option.key, 0, 0, 28, 0)
    love.graphics.pop()

    love.graphics.setColor(0.18, 0.11, 0.06, 1.0 * a)
    pushUIFont()
    local def = buildingDefs[option.key]
    local costText = ""
    if def and def.cost and def.cost.wood then
      costText = string.format(" (Cost: %d wood)", def.cost.wood)
    end
    love.graphics.print(option.label .. costText, ox + 52, oy + 12)
    popUIFont()

    -- shortcuts for quick build (if defined)
    local shortcut = (option.key == 'house' and 'H') or (option.key == 'lumberyard' and 'L') or (option.key == 'warehouse' and 'W') or (option.key == 'market' and 'M') or (option.key == 'builder' and 'B') or (option.key == 'farm' and 'F') or nil
    if shortcut then
      love.graphics.setColor(0.18, 0.11, 0.06, 0.75)
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

  local handheld = state.ui._handheldMode
  local w, h = handheld and 360 or 520, handheld and 180 or 200
  local screenW, screenH = love.graphics.getDimensions()
  local x = (screenW - w) / 2
  local y = (screenH - h) / 2
  drawParchmentPanel(x, y, w, h)

  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  local pop = state.game.population
  if handheld then pushTinyFont() end
  love.graphics.print(string.format('Villagers: %d/%d  Cap:%d', pop.assigned or 0, pop.total or 0, pop.capacity or 0), x + 12, y + 12)

  local btns = {}
  local rowY = y + (handheld and 48 or 64)
  local rowH = handheld and 22 or 28
  local rowIndex = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'lumberyard' or b.type == 'builder' or b.type == 'farm' or b.type == 'research' then
      rowIndex = rowIndex + 1
      local name = (b.type == 'lumberyard') and 'Lumberyard' or (b.type == 'builder' and 'Builders Workplace' or (b.type == 'farm' and 'Farm' or 'Research Center'))
      local maxSlots = (b.type == 'lumberyard') and (state.buildingDefs.lumberyard.numWorkers or 0)
        or (b.type == 'builder' and (state.buildingDefs.builder.numWorkers or 0)
        or (b.type == 'farm' and (state.buildingDefs.farm.numWorkers or 0) or (state.buildingDefs.research.numWorkers or 0)))

      -- Handheld focus highlight for current row
      if handheld then
        local isFocused = (state.ui._villagersPanelFocus or 1) == rowIndex
        if isFocused then
          love.graphics.setColor(0.20, 0.78, 0.30, 0.15)
          love.graphics.rectangle('fill', x + 8, rowY - 6, w - 16, rowH + 8, 6, 6)
        end
      end

      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(string.format('%s %d/%d  (%d,%d)', name, b.assigned or 0, maxSlots, b.tileX, b.tileY), x + 12, rowY)
      local btnW, btnH = handheld and 22 or 28, handheld and 20 or 24
      local remX, remY = x + w - 76, rowY - 4
      local addX, addY = x + w - 40, rowY - 4
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', remX - 2, remY + 2, btnW + 4, btnH + 4, 6, 6)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', remX, remY, btnW, btnH, 6, 6)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', remX, remY, btnW, btnH, 6, 6)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.printf('-', remX, remY + 4, btnW, 'center')
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', addX - 2, addY + 2, btnW + 4, btnH + 4, 6, 6)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', addX, addY, btnW, btnH, 6, 6)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', addX, addY, btnW, btnH, 6, 6)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.printf('+', addX, addY + 4, btnW, 'center')
      table.insert(btns, { type = b.type, b = b, add = { x = addX, y = addY, w = btnW, h = btnH }, rem = { x = remX, y = remY, w = btnW, h = btnH } })
      rowY = rowY + rowH
    end
  end
  state.ui._villagersPanelButtons = btns
  if handheld then popUIFont() end
end

function ui.drawBuildQueue(state)
  if not state.ui.isBuildQueueOpen then return end
  local screenW, screenH = love.graphics.getDimensions()
  local handheld = state.ui._handheldMode
  local w, h = handheld and 520 or 560, handheld and 260 or 260
  -- Always center the panel in the middle of the screen
  local x = (screenW - w) / 2
  local y = (screenH - h) / 2
  drawParchmentPanel(x, y, w, h)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  if handheld then pushTinyFont() end
  
  -- Show selection status in title
  local title = 'Build Queue'
  if handheld and state.ui._queueSelectedIndex then
    title = 'Build Queue — Reordering'
  end
  love.graphics.print(title, x + 12, y + 12)
  
  local headerY = y + 36
  local rowH = handheld and 28 or 34
  state.ui._queueButtons = {}
  state.ui._queueHoverId = nil
  state.ui._queueLayout = { headerY = headerY, rowH = rowH, x = x, y = y, w = w, h = h }
  local byId = {}
  for _, b in ipairs(state.game.buildings) do byId[b.id] = b end
  local qraw = state.game.buildQueue or {}
  if #qraw == 0 then
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print('Queue is empty. Place buildings to add plans here.', x + 12, headerY)
    if handheld then popUIFont() end
    return
  end
  
  -- Show controls hint in handheld mode
  if handheld then
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    local hintText = state.ui._queueSelectedIndex and 'Stick: Move • A: Deselect • B: Close' or 'Stick: Navigate • A: Select • B: Close'
    love.graphics.print(hintText, x + 12, y + h - 24)
  end
  -- draw in current queue order; top is highest priority
  local drag = state.ui._queueDrag
  local mx, my = ui.getPointer()
  local dropIndex = nil
  for i, q in ipairs(qraw) do
    local b = byId[q.id]
    if b then
      local ry = headerY + (i - 1) * rowH
      -- background per row
      local rowRect = { x = x + 8, y = ry, w = w - 16, h = rowH - 4 }
      local hovered = utils.isPointInRect(mx, my, rowRect.x, rowRect.y, rowRect.w, rowRect.h)
      if hovered then state.ui._queueHoverId = b.id end
      local isDraggedRow = (drag and drag.id == b.id)
      if not isDraggedRow then
        -- fancier row: shadow + inner plate
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle('fill', rowRect.x + 2, rowRect.y + 3, rowRect.w, rowRect.h, 6, 6)
        love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
        love.graphics.rectangle('fill', rowRect.x, rowRect.y, rowRect.w, rowRect.h, 6, 6)
        love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
        love.graphics.rectangle('line', rowRect.x, rowRect.y, rowRect.w, rowRect.h, 6, 6)
        -- Handheld focus highlight for left-stick navigation
        local focused = handheld and ((state.ui._queueFocusIndex or 1) == i)
        local selected = handheld and (state.ui._queueSelectedIndex == i)
        if selected then
          -- Selected item for reordering (bright highlight)
          love.graphics.setColor(0.95, 0.7, 0.2, 0.4)
          love.graphics.rectangle('fill', rowRect.x + 1, rowRect.y + 1, rowRect.w - 2, rowRect.h - 2, 6, 6)
          love.graphics.setColor(0.95, 0.7, 0.2, 0.8)
          love.graphics.rectangle('line', rowRect.x + 2, rowRect.y + 2, rowRect.w - 4, rowRect.h - 4, 6, 6)
        elseif hovered or focused then
          -- Regular focus/hover
          love.graphics.setColor(0.20, 0.78, 0.30, 0.15)
          love.graphics.rectangle('fill', rowRect.x + 3, rowRect.y + 3, rowRect.w - 6, rowRect.h - 6, 6, 6)
        end
        love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
        -- icon
        buildings.drawIcon(b.type, x + 18, ry + (rowH/2), handheld and 18 or 24, 0)
        -- name + coords
        love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
        local status
        if b.construction and b.construction.complete then status = 'Complete'
        elseif b.construction and b.construction.waitingForResources then status = 'Waiting'
        elseif b._claimedBy then status = 'Building…' else status = 'Ready' end
        love.graphics.print(string.format('%s  (%d,%d)  [%s]', b.type, b.tileX, b.tileY, status), x + 44, ry + (handheld and 6 or 8))
        -- On handheld, omit pause/remove buttons and provide simple reorder hints
        if not handheld then
          local btnW, btnH = 24, 20
          local upx = x + w - 200; local upy = ry + 6
          local dnx = upx + btnW + 6; local dny = upy
          love.graphics.setColor(0.35,0.22,0.12,1.0)
          love.graphics.rectangle('fill', upx-2, upy+2, btnW+4, btnH+4, 6, 6)
          love.graphics.setColor(0.95,0.82,0.60,1.0)
          love.graphics.rectangle('fill', upx, upy, btnW, btnH, 6, 6)
          love.graphics.setColor(0.78,0.54,0.34,1.0)
          love.graphics.rectangle('line', upx, upy, btnW, btnH, 6, 6)
          love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
          love.graphics.printf('^', upx, upy + 2, btnW, 'center')
          love.graphics.setColor(0.35,0.22,0.12,1.0)
          love.graphics.rectangle('fill', dnx-2, dny+2, btnW+4, btnH+4, 6, 6)
          love.graphics.setColor(0.95,0.82,0.60,1.0)
          love.graphics.rectangle('fill', dnx, dny, btnW, btnH, 6, 6)
          love.graphics.setColor(0.78,0.54,0.34,1.0)
          love.graphics.rectangle('line', dnx, dny, btnW, btnH, 6, 6)
          love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
          love.graphics.printf('v', dnx, dny + 2, btnW, 'center')
        end
        state.ui._queueButtons[#state.ui._queueButtons + 1] = {
          id = b.id,
          row = i,
          rowRect = rowRect
        }
      end
      -- compute tentative drop index while dragging (desktop drag)
      if drag then
        local midY = ry + rowH / 2
        if not dropIndex and my < midY then dropIndex = i end
      end
    end
  end
  if drag then
    -- default drop at end
    dropIndex = dropIndex or (#qraw + 1)
    state.ui._queueDropIndex = dropIndex
    -- insertion line
    local idx = math.max(1, math.min(dropIndex, #qraw + 1))
    local lineY
    if idx == 1 then lineY = headerY - 2 else lineY = headerY + (idx - 1) * rowH - 4 end
    love.graphics.setColor(1, 1, 0.5, 0.7)
    love.graphics.rectangle('fill', x + 10, lineY, w - 20, 2)
  else
    state.ui._queueDropIndex = nil
  end

  -- Handheld hint footer
  if handheld then
    local hint = state.ui._queueReorderActive and 'Flick Up/Down to move. B to finish.' or 'A: Select to reorder. Up/Down: change focus.'
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle('fill', x + 8, y + h - 30 + 3, w - 16, 24, 6, 6)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', x + 8, y + h - 30, w - 16, 24, 6, 6)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf(hint, x + 8, y + h - 26, w - 16, 'center')
  end

  if handheld then popUIFont() end
end

-- Minimap (top-right). Shows roads, trees, buildings, and camera viewport.
function ui.drawMiniMap(state)
  local TILE = constants.TILE_SIZE
  local world = state.world
  if world.tilesX <= 0 or world.tilesY <= 0 then return end

  local screenW, screenH = love.graphics.getDimensions()
  local padding = 16
  local x, y, mapW, mapH, scale

  if state.ui.isMinimapFullscreen then
    -- Fullscreen minimap mode
    local maxW = screenW - padding * 2
    local maxH = screenH - padding * 2
    
    -- Calculate scale to fit either width or height
    local scaleW = maxW / world.tilesX
    local scaleH = maxH / world.tilesY
    scale = math.min(scaleW, scaleH)
    
    mapW = world.tilesX * scale
    mapH = world.tilesY * scale
    
    -- Center the map on screen
    x = (screenW - mapW) / 2
    y = (screenH - mapH) / 2
  else
    -- Regular minimap mode
    local desiredW = isSmallScreen() and 140 or 180
    scale = desiredW / world.tilesX
    mapW = desiredW
    mapH = world.tilesY * scale

    -- Place at top-right; if villagers panel open, place below it
    local yOffset = isSmallScreen() and 12 or 16
    x = screenW - padding - mapW
    y = yOffset
  end

  -- Store for click handling
  state.ui._miniMap = { x = x, y = y, w = mapW, h = mapH, scale = scale }

  -- Fullscreen background overlay
  if state.ui.isMinimapFullscreen then
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
  end

  -- Opaque grassy backdrop only (no outer frame)
  love.graphics.setColor(0.15, 0.26, 0.14, 1.0)
  love.graphics.rectangle('fill', x, y, mapW, mapH)
  love.graphics.setColor(0.10, 0.18, 0.10, 0.9)
  love.graphics.rectangle('line', x, y, mapW, mapH)

  -- Draw roads
  if state.game.roads then
    -- mimic road tone on grass
    love.graphics.setColor(0.16, 0.17, 0.18, 0.95)
    for _, rd in pairs(state.game.roads) do
      local rx = x + rd.tileX * scale
      local ry = y + rd.tileY * scale
      love.graphics.rectangle('fill', rx, ry, scale, scale)
    end
  end

  -- Draw trees
  -- trees: deeper green dots
  love.graphics.setColor(0.20, 0.55, 0.22, 1.0)
  for _, t in ipairs(state.game.trees) do
    if t.alive then
      local tx = x + t.tileX * scale
      local ty = y + t.tileY * scale
      love.graphics.rectangle('fill', tx + scale * 0.2, ty + scale * 0.2, math.max(1, scale * 0.6), math.max(1, scale * 0.6))
    end
  end

  -- Draw buildings
  for _, b in ipairs(state.game.buildings) do
    local bx = x + b.tileX * scale
    local by = y + b.tileY * scale
    -- building base with shadow
    love.graphics.setColor(0,0,0,0.25)
    love.graphics.rectangle('fill', bx+1, by+1, scale, scale)
    love.graphics.setColor(b.color[1], b.color[2], b.color[3], 1)
    love.graphics.rectangle('fill', bx, by, scale, scale)
    love.graphics.setColor(1,1,1,0.12)
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

  -- Exit hint for fullscreen mode
  if state.ui.isMinimapFullscreen then
    pushTinyFont()
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("Left stick to navigate • D-pad Right/A/B to exit", x + 10, y + mapH - 20)
    popUIFont()
  end
end

-- Optional: small corner badge hint for compact objectives card
-- removed hint chip for compact objectives panel

-- Small D-pad hint (handheld only) in lower-left corner
function ui.drawDpadHint(state)
  if not state.ui._handheldMode then return end
  local screenW, screenH = love.graphics.getDimensions()
  -- Anchor in lower-left with some padding; position whole cluster from bottom-left
  local pad = 12
  -- metrics depend on font, compute left-chip width to keep within screen
  pushTinyFont()
  local fontForLayout = love.graphics.getFont()
  local leftLabelMeasure = 'Objectives'
  local leftChipW = (fontForLayout:getWidth(leftLabelMeasure) + 8)
  popUIFont()
  local cx = pad + leftChipW + 12 + 26 -- left chip + gap + baseR
  local cy = screenH - pad - 26 - (love.graphics.getFont():getHeight() + 10)

  -- Fancy D-pad metrics
  local baseR = 26            -- round base radius
  local armW  = 12            -- arm thickness
  local armL  = 16            -- arm length from center to tip
  local gap   = 4             -- center gap

  -- Back plate for readability
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle('fill', cx - (baseR + 14), cy - (baseR + 14), (baseR + 14) * 2, (baseR + 14) * 2, 6, 6)

  -- Round base with subtle shading
  love.graphics.setColor(0.12, 0.12, 0.13, 0.95)
  love.graphics.circle('fill', cx, cy, baseR)
  love.graphics.setColor(0.18, 0.18, 0.19, 1.0)
  love.graphics.circle('line', cx, cy, baseR)
  -- highlight/shadow sweep
  love.graphics.setColor(1, 1, 1, 0.06)
  love.graphics.arc('fill', cx, cy, baseR, -1.05 * math.pi, -0.55 * math.pi)
  love.graphics.setColor(0, 0, 0, 0.10)
  love.graphics.arc('fill', cx, cy, baseR, 0.35 * math.pi, 0.75 * math.pi)

  -- Cross arms (rounded)
  local armColor = { 0.88, 0.88, 0.90, 0.96 }
  local edgeColor = { 0.22, 0.22, 0.24, 1.0 }
  love.graphics.setColor(armColor)
  -- up
  love.graphics.rectangle('fill', cx - armW/2, cy - gap/2 - armL, armW, armL, 3, 3)
  -- down
  love.graphics.rectangle('fill', cx - armW/2, cy + gap/2, armW, armL, 3, 3)
  -- left
  love.graphics.rectangle('fill', cx - gap/2 - armL, cy - armW/2, armL, armW, 3, 3)
  -- right
  love.graphics.rectangle('fill', cx + gap/2, cy - armW/2, armL, armW, 3, 3)
  -- outlines
  love.graphics.setColor(edgeColor)
  love.graphics.rectangle('line', cx - armW/2, cy - gap/2 - armL, armW, armL, 3, 3)
  love.graphics.rectangle('line', cx - armW/2, cy + gap/2, armW, armL, 3, 3)
  love.graphics.rectangle('line', cx - gap/2 - armL, cy - armW/2, armL, armW, 3, 3)
  love.graphics.rectangle('line', cx + gap/2, cy - armW/2, armL, armW, 3, 3)

  -- Center diamond
  love.graphics.setColor(0.92, 0.92, 0.94, 1)
  love.graphics.rectangle('fill', cx - gap/2, cy - gap/2, gap, gap, 2, 2)
  love.graphics.setColor(edgeColor)
  love.graphics.rectangle('line', cx - gap/2, cy - gap/2, gap, gap, 2, 2)

  -- Labels (kept outside of the dpad, aligned and with background chips)
  local upLabel = 'Queue'
  local downLabel = 'Villagers'
  local leftLabel = 'Objectives'
  local rightLabel = 'Map'

  pushTinyFont()
  local font = love.graphics.getFont()
  local function drawChip(text, tx, ty, align)
    local w = font:getWidth(text)
    local h = font:getHeight()
    local x0 = tx
    if align == 'center' then x0 = tx - w/2 end
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle('fill', x0 - 4, ty - 2, w + 8, h + 4, 4, 4)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.print(text, x0, ty)
  end

  local extent = baseR + 10
  drawChip(upLabel,   cx, cy - extent - font:getHeight() - 4, 'center')
  drawChip(downLabel, cx, cy + extent + 6, 'center')
  -- Left chip anchored to screen left
  drawChip(leftLabel, pad, cy - font:getHeight()/2, 'left')
  drawChip(rightLabel, cx + extent + 6, cy - font:getHeight()/2, 'left')
  popUIFont()
end

function ui.drawHUD(state)
  pushUIFont()
  local handheld = state.ui._handheldMode
  local x = handheld and 12 or (ui.villagersButton.x + ui.villagersButton.width + 16)
  local y = handheld and 8 or 16
  local w = handheld and 260 or 600
  local h = handheld and 72 or 100
  -- parchment theme like objectives
  if not handheld then
    drawParchmentPanel(x, y, w, h)
    -- expose HUD bounds so prompts can anchor just below it on handheld/desktop
    state.ui._hudBounds = { x = x, y = y, w = w, h = h }
  end

  if handheld then
    pushTinyFont()
  else
    love.graphics.setColor(colors.text)
  end
  local baseWood = math.floor(state.game.resources.wood + 0.5)
  local storedWood = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      storedWood = storedWood + b.storage.wood
    end
  end
  local totalWood = baseWood + storedWood
  local lineX = x + 12
  local lineY = y + 12
  -- Precompute food and time for both modes
  local baseFood = math.floor((state.game.resources.food or 0) + 0.5)
  local storedFood = 0
  for _, b in ipairs(state.game.buildings) do
    if (b.type == 'market' or b.type == 'builder') and b.storage and b.storage.food then
      storedFood = storedFood + b.storage.food
    end
  end
  local totalFood = baseFood + storedFood
  local hours = math.floor(state.time.normalized * 24) % 24
  local minutes = math.floor((state.time.normalized * 24 - hours) * 60)
  local tnorm = state.time.normalized
  local isDay = (tnorm >= 0.25 and tnorm < 0.75)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  if handheld then
    -- Compose single-line HUD and size parchment to fit (no extra whitespace)
    local font = love.graphics.getFont()
    local parts = {}
    local woodStr = string.format("Wood:%d", totalWood)
    table.insert(parts, woodStr)
    local foodStr = string.format("Food:%d", totalFood)
    table.insert(parts, foodStr)
    local hasResearch = false
    for _, b in ipairs(state.game.buildings) do if b.type == 'research' then hasResearch = true break end end
    local researchStr
    if hasResearch then
      local R = state.game.research or { progress = 0, required = 60 }
      researchStr = string.format("Res:%d/%d", math.floor(R.progress or 0), R.required or 60)
      table.insert(parts, researchStr)
    end
    local timeStr = string.format("%02d:%02d%s", hours, minutes, isDay and "D" or "N")
    table.insert(parts, timeStr)
    local speedStr = string.format("%dx", state.time.speed or 1)
    table.insert(parts, speedStr)

    local sep = "   "
    local label = table.concat(parts, sep)
    local textW = font:getWidth(label)
    local textH = font:getHeight()
    local padH = 12
    local padW = 12
    local neededW = textW + padW * 2
    local neededH = textH + padH * 2
    -- redraw parchment with exact size needed
    w = math.min(neededW, love.graphics.getWidth() - x - 12)
    drawParchmentPanel(x, y, w, neededH)
    state.ui._hudBounds = { x = x, y = y, w = w, h = neededH }
    -- match prompt text color
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(label, lineX, lineY)
  else
    love.graphics.print(string.format("Wood: %d", totalWood), lineX, lineY)
  end
  local foodLabel = string.format("Food: %d", totalFood)
  if not handheld then
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(foodLabel, x + 12, y + 32)
    local fw = love.graphics.getFont():getWidth(foodLabel)
    state.ui._foodButton = { x = x + 10, y = y + 30, w = fw + 6, h = 18 }
  else
    local fw = love.graphics.getFont():getWidth(foodLabel)
    state.ui._foodButton = { x = x + 10, y = y + 10, w = fw + 6, h = 18 }
  end

  -- Research progress (if any Research Center exists)
  do
    local hasResearch = false
    for _, b in ipairs(state.game.buildings) do if b.type == 'research' then hasResearch = true break end end
    if hasResearch and (not handheld) then
      local R = state.game.research or { points = 0, required = 60, progress = 0 }
      local label = string.format("Research: %s %d/%d", R.target or 'Project', math.floor(R.progress or 0), R.required or 60)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(label, x + 12, y + 52)
      -- small progress bar
      local bw, bh = 180, 8
      local px, py = x + 12, y + 68
      love.graphics.setColor(0, 0, 0, 0.35)
      love.graphics.rectangle('fill', px, py, bw, bh, 4, 4)
      local p = math.min(1, (R.progress or 0) / (R.required or 60))
      love.graphics.setColor(0.30, 0.6, 0.95, 1)
      love.graphics.rectangle('fill', px, py, bw * p, bh, 4, 4)
      love.graphics.setColor(colors.uiPanelOutline)
      love.graphics.rectangle('line', px, py, bw, bh, 4, 4)
    end
  end

  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  if not handheld then
    love.graphics.print(string.format("Time: %02d:%02d (%s)", hours, minutes, isDay and "Day" or "Night"), x + 220, y + 12)
    love.graphics.print(string.format("Speed: %dx", state.time.speed or 1), x + 400, y + 12)
  end

  local btnW, btnH = handheld and 24 or 36, handheld and 16 or 22
  local s1x = x + (handheld and 14 or 390); local s1y = y + (handheld and (h - 30) or 52)
  local s2x = s1x + btnW + 6; local s2y = s1y
  local s4x = s2x + btnW + 6; local s4y = s1y
  local s8x = s4x + btnW + 6; local s8y = s1y
  local function drawSpeed(xb, yb, label, active)
    -- parchment mini button
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.rectangle('fill', xb - 2, yb - 2, btnW + 4, btnH + 4, 6, 6)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', xb, yb, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle('line', xb, yb, btnW, btnH, 6, 6)
    if active then
      love.graphics.setColor(0.20, 0.78, 0.30, 0.25)
      love.graphics.rectangle('fill', xb+2, yb+2, btnW-4, btnH-4, 4, 4)
    end
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf(label, xb, yb + 4, btnW, 'center')
  end
  if not handheld then
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
  else
    state.ui._speedButtons = nil
  end

  if (not handheld) and state.ui.isPlacingBuilding and state.ui.selectedBuildingType and not state.ui.isPaused then
    local def = state.buildingDefs[state.ui.selectedBuildingType]
    if def and def.cost and def.cost.wood then
      local costStr = string.format("Cost: %d wood", def.cost.wood)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(costStr, x + 12, y + 50)
    end
    if state.ui.selectedBuildingType == "lumberyard" then
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(string.format("Radius: %d tiles, Workers: %d", state.buildingDefs.lumberyard.radiusTiles, state.buildingDefs.lumberyard.numWorkers), x + 12, y + 68)
    end
  end

  -- (removed) road instructions are now shown as a prompt when road mode is toggled

  -- demolish hint
  if (not handheld) and state.ui.isDemolishMode then
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print("Demolish Mode: click a building to remove (refund 50%)", x + 12, y + 60)
  end

  if handheld then popUIFont() end
  if not handheld then ui.drawVillagersPanel(state) end
  popUIFont()
end

function ui.drawFoodPanel(state)
  if not state.ui.isFoodPanelOpen then return end
  local screenW, screenH = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle('fill', 0, 0, screenW, screenH)

  local panelW = 520
  local panelH = 360
  local px = (screenW - panelW) / 2
  local py = (screenH - panelH) / 2

  love.graphics.setColor(0,0,0,0.25)
  love.graphics.rectangle('fill', px + 3, py + 4, panelW, panelH, 10, 10)
  love.graphics.setColor(0.16,0.23,0.16,0.96)
  love.graphics.rectangle('fill', px, py, panelW, panelH, 10, 10)
  love.graphics.setColor(1,1,1,0.06)
  love.graphics.rectangle('fill', px + 6, py + 6, panelW - 12, math.max(16, panelH * 0.18), 8, 8)
  love.graphics.setColor(colors.uiPanelOutline)
  love.graphics.rectangle('line', px, py, panelW, panelH, 10, 10)

  local ox = px + 18
  local oy = py + 16
  love.graphics.setColor(colors.text)
  love.graphics.printf('Food Overview', px, oy, panelW, 'center')
  oy = oy + 28

  -- Aggregates
  local baseFood = math.floor((state.game.resources.food or 0) + 0.5)
  local marketsFood, builderFood = 0, 0
  local capacity = 0
  local coveredHouses, totalHouses = 0, 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'market' then
      if b.storage and b.storage.food then marketsFood = marketsFood + b.storage.food end
      capacity = capacity + 50 -- nominal per market
    elseif b.type == 'builder' then
      if b.storage and b.storage.food then builderFood = builderFood + b.storage.food end
    elseif b.type == 'house' and b.construction and b.construction.complete then
      totalHouses = totalHouses + 1
      -- coverage check
      local inRadius = false
      for _, m in ipairs(state.game.buildings) do
        if m.type == 'market' then
          local dx = m.tileX - b.tileX
          local dy = m.tileY - b.tileY
          local r = (state.buildingDefs.market.radiusTiles or 0)
          if dx*dx + dy*dy <= r*r then inRadius = true; break end
        end
      end
      if inRadius then coveredHouses = coveredHouses + 1 end
    end
  end
  local totalFood = baseFood + marketsFood + builderFood
  local pop = state.game.population.total or 0
  local tonightDemand = pop
  local deficit = math.max(0, tonightDemand - (marketsFood))

  -- Text blocks
  love.graphics.print(string.format('Total Food: %d', totalFood), ox, oy)
  oy = oy + 20
  love.graphics.print(string.format("In Markets: %d", marketsFood), ox, oy)
  oy = oy + 20
  love.graphics.print(string.format("Other Storage: %d", baseFood + builderFood), ox, oy)
  oy = oy + 20
  love.graphics.print(string.format("Tonight's Demand: %d", tonightDemand), ox, oy)
  oy = oy + 20
  local txt = string.format('Deficit: %d', deficit)
  if deficit > 0 then love.graphics.setColor(0.9, 0.2, 0.2, 1) else love.graphics.setColor(0.2, 0.9, 0.3, 1) end
  love.graphics.print(txt, ox, oy)
  love.graphics.setColor(colors.text)
  oy = oy + 28
  love.graphics.print(string.format('Coverage: %d houses covered / %d total', coveredHouses, totalHouses), ox, oy)
  oy = oy + 24

  -- Markets table
  love.graphics.print('Markets:', ox, oy)
  oy = oy + 18
  local colX = { ox, ox + 220, ox + 360 }
  love.graphics.print('Location', colX[1], oy)
  love.graphics.print('Stock',    colX[2], oy)
  love.graphics.print('Radius',   colX[3], oy)
  oy = oy + 14
  love.graphics.setColor(1,1,1,0.15)
  love.graphics.rectangle('fill', ox, oy, panelW - 36, 1)
  love.graphics.setColor(colors.text)
  oy = oy + 8
  for _, m in ipairs(state.game.buildings) do
    if m.type == 'market' then
      love.graphics.print(string.format('(%d,%d)', m.tileX, m.tileY), colX[1], oy)
      love.graphics.print(string.format('%d', (m.storage and m.storage.food) or 0), colX[2], oy)
      love.graphics.print(string.format('%d', (state.buildingDefs.market.radiusTiles or 0)), colX[3], oy)
      oy = oy + 16
    end
  end

  -- Close hint
  love.graphics.setColor(1,1,1,0.6)
  love.graphics.printf("Press F or click outside to close", px, py + panelH - 26, panelW, 'center')
end

function ui.drawMissionPanel(state)
  local M = state.mission
  if not M or not M.active then return end
  pushUIFont()
  -- If mission selector is open, draw it instead for clarity
  if state.ui.isMissionSelectorOpen then
    local screenW, screenH = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
    local w, h = 420, 260
    local x, y = (screenW - w) / 2, (screenH - h) / 2
    love.graphics.setColor(0,0,0,0.25)
    love.graphics.rectangle('fill', x + 3, y + 4, w, h, 10, 10)
    love.graphics.setColor(0.16,0.23,0.16,0.96)
    love.graphics.rectangle('fill', x, y, w, h, 10, 10)
    love.graphics.setColor(1,1,1,0.06)
    love.graphics.rectangle('fill', x + 6, y + 6, w - 12, math.max(16, h * 0.18), 8, 8)
    love.graphics.setColor(colors.uiPanelOutline)
    love.graphics.rectangle('line', x, y, w, h, 10, 10)
    love.graphics.setColor(colors.text)
    love.graphics.print('Mission Selector (Debug)', x + 12, y + 12)
    local options = {
      { label = 'Stage 1: First Foundations', id = 1 },
      { label = 'Stage 2: Food and Logistics', id = 2 },
      { label = 'Stage 3: Night Market City', id = 3 },
      { label = "Stage 4: Builders' Pride", id = 4 },
      { label = 'Stage 5: Green Belt', id = 5 },
      { label = 'Stage 6: Festival Day', id = 6 },
      { label = 'Stage 7: Master Planner', id = 7 }
    }
    state.ui._missionSelectorButtons = {}
    state.ui._missionSelectorFocus = state.ui._missionSelectorFocus or 1
    local oy = y + 40
    for i, opt in ipairs(options) do
      local btn = { x = x + 12, y = oy, w = w - 24, h = 30, id = opt.id, label = opt.label }
      local mx, my = ui.getPointer()
      local hovered = utils.isPointInRect(mx, my, btn.x, btn.y, btn.w, btn.h)
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', btn.x - 2, btn.y + 2, btn.w + 4, btn.h + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', btn.x, btn.y, btn.w, btn.h, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', btn.x, btn.y, btn.w, btn.h, 8, 8)
      if hovered or state.ui._missionSelectorFocus == i then love.graphics.setColor(0.20, 0.78, 0.30, 0.18); love.graphics.rectangle('fill', btn.x+2, btn.y+2, btn.w-4, btn.h-4, 6, 6) end
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.printf(opt.label, btn.x, btn.y + 8, btn.w, 'center')
      table.insert(state.ui._missionSelectorButtons, btn)
      oy = oy + 36
    end
    return
  end
  -- Layout calculations with dynamic height and text wrapping
  local screenW, screenH = love.graphics.getDimensions()
  -- Scale panel width; smaller on handheld
  local handheld = state.ui._handheldMode
  local fullscreen = handheld and state.ui.isMissionFullscreen
  if handheld then pushTinyFont() end
  -- Compact card for handheld corner; full overlay if fullscreen flag
  local w
  if fullscreen then
    w = math.min(560, math.max(420, math.floor(screenW * 0.8)))
  else
    w = handheld and 240 or math.min(560, math.max(420, math.floor(screenW * 0.45)))
  end
  local paddingTop, paddingBottom
  if handheld and not fullscreen then
    paddingTop, paddingBottom = 8, 2
  else
    paddingTop, paddingBottom = 12, 12
  end
  local titleH = (handheld and not fullscreen) and 16 or (handheld and 18 or 24)
  local font = love.graphics.getFont()
  local lineH = font:getHeight()
  local contentH = titleH + 6
  local textW = w - 44
  -- Measure objective blocks
  local objectivesList = M.objectives or {}
  local objectivesCount = #objectivesList
  for idx, o in ipairs(objectivesList) do
    if handheld and not fullscreen then
      -- Compact row: title + small progress bar/label
      local rowH = 20
      local bh = (o.target and o.target > 1) and 6 or 0
      local spacing = (idx < objectivesCount) and 6 or 0
      -- Actual drawn increment per row: header(18) + bar(bh) + spacing
      contentH = contentH + 18 + bh + spacing
    else
      local _, lines = font:getWrap(o.text or '', textW)
      local linesH = math.max(lineH, #lines * lineH)
      local barH = (o.target and o.target > 1) and (10 + 8) or 0
      contentH = contentH + math.max(24, linesH) + barH + 10
    end
  end
  if M.completed and ((not handheld) or fullscreen) then contentH = contentH + 20 end
  local h = contentH + paddingTop + paddingBottom
  local x
  local y
  if fullscreen then
    -- Center fullscreen overlay
    x = (screenW - w) / 2
    y = (screenH - h) / 2
    -- darken background
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
  else
    -- Corner card (lower-right), tight margins
    x = screenW - w - 8
    y = screenH - h - 8
  end

  -- Pixel-art parchment theme (panel frame)
  local function drawPixelFrame(px, py, pw, ph)
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.rectangle('fill', px - 4, py - 4, pw + 8, ph + 8)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.rectangle('line', px - 4, py - 4, pw + 8, ph + 8)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', px, py, pw, ph)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle('line', px, py, pw, ph)
  end
  drawPixelFrame(x, y, w, h)

  -- Title in pixel style (truncate on compact card)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  local title = 'MISSION: ' .. string.upper(M.name or 'Unknown')
  if handheld and not fullscreen then
    title = truncateToWidth(title, w - 24)
  end
  love.graphics.print(title, x + 12, y + 6)

  local oy = y + 10 + titleH
  for idx, o in ipairs(M.objectives or {}) do
    -- draw scroll-like strip
    -- Recompute wrapped lines per objective to size the strip correctly
    local _, wrapped = font:getWrap(fullscreen and (o.text or '') or '', textW)
    local rowH
    if handheld and not fullscreen then
      -- Compact row height for handheld corner: title + slim progress
      rowH = 20
    else
      rowH = math.max(handheld and 18 or 24, #wrapped * lineH + 2)
    end
    local stripW = w - 24
    local sx = x + 12
    local sy = oy - 4
    -- end caps
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle('fill', sx, sy, 10, rowH + 8)
    love.graphics.rectangle('fill', sx + stripW - 10, sy, 10, rowH + 8)
    -- body
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', sx + 10, sy, stripW - 20, rowH + 8)
    love.graphics.setColor(0.62, 0.36, 0.20, 1.0)
    love.graphics.rectangle('line', sx, sy, stripW, rowH + 8)

    -- status badge (fancy smooth check)
    if o.done then
      drawFancyCheck(sx + 12, sy + 12, 8, o.completePulse)
    end

    -- Wrapped text in uppercase for pixel feel (only in fullscreen or desktop)
    if (not handheld) or fullscreen then
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      local tx = sx + 22
      local tw = stripW - 44
      local text = (o.text or '')
      -- Append live state hints for select objectives
      if state.mission and state.mission.stage == 5 then
        if o.id == 'road_loop' then
          local len = state.mission._loopLen or 0
          text = text .. string.format("  (%d/12 tiles)", math.min(12, len))
        elseif o.id == 'logistics_day' then
          local pct = state.mission._logisticsPct or 0
          text = text .. string.format("  (Storage %d%% full)", pct)
        end
      end
      love.graphics.printf(text, tx, sy + 6, tw, 'left')
    else
      -- Compact: show only the witty title extracted from text (before colon)
      local full = o.text or ''
      local titleOnly = full:match('^([^:]+)') or full
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(titleOnly, sx + 22, sy + 2)
    end

    -- Progress bar (pixel)
    local blockBottom = sy + rowH + 2
    local isLast = (idx == #(M.objectives or {}))
    if o.target and o.target > 1 then
      local bw, bh = stripW - 28, handheld and 6 or 8
      local bx, by = sx + 14, blockBottom
      local p = math.min(1, (o.current or 0) / o.target)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('fill', bx - 1, by - 1, bw + 2, bh + 2)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', bx, by, bw, bh)
      love.graphics.setColor(0.35, 0.75, 0.35, 1.0)
      love.graphics.rectangle('fill', bx, by, bw * p, bh)
      -- sparkle pixels at the head of the fill
      local headX = bx + math.floor(bw * p)
      love.graphics.setColor(0.95, 0.85, 0.4, 0.9)
      love.graphics.rectangle('fill', headX, by - 2, 2, 2)
      love.graphics.rectangle('fill', headX + 3, by + bh, 2, 2)
      love.graphics.rectangle('fill', headX - 3, by + bh, 2, 2)
      -- Progress label, right-aligned and readable
      local label
      if o.id == 'logistics_day' and state.time and state.time.dayLength then
        local dl = state.time.dayLength
        local hours = math.min(12, ((o.current or 0) / dl) * 12)
        local hoursInt = math.floor(hours)
        label = string.format('%d / 12 hours', hoursInt)
      else
        label = string.format('%d / %d', math.floor(o.current or 0), o.target)
      end
      local lw = font:getWidth(label)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      if handheld then
        if fullscreen then
          -- Fullscreen handheld: align with title text baseline
          love.graphics.print(label, sx + (stripW - 14) - lw, sy + 6)
        else
          -- Compact panel
          love.graphics.print(label, sx + (stripW - 14) - lw, sy + 2)
        end
      else
        -- Desktop
        love.graphics.print(label, bx + bw - lw, by - 12)
      end
      oy = by + bh + ((handheld and not fullscreen) and (isLast and 0 or 6) or (handheld and 10 or 12))
    else
      -- No bar: still show progress label (0/1 or 1/1) on the right
      local label = string.format('%d / %d', math.floor(o.current or 0), math.max(1, o.target or 1))
      local lw = font:getWidth(label)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      local labelY = (handheld and fullscreen) and (sy + 6) or (sy + 2)
      love.graphics.print(label, sx + (stripW - 14) - lw, labelY)
      oy = blockBottom + ((handheld and not fullscreen) and (isLast and 0 or 6) or 8)
    end
  end
  if M.completed and ((not handheld) or fullscreen) then
    love.graphics.setColor(1, 1, 0.6, 1)
    love.graphics.print('Completed!', x + 12, y + h - (handheld and 18 or 22))
  end
  popUIFont()
end

function ui.drawPrompt(state)
  local list = state.ui.prompts or {}
  if #list == 0 then return end
  local screenW, screenH = love.graphics.getDimensions()
  local handheld = state.ui._handheldMode
  local baseX = 16
  -- anchor just below HUD on handheld; otherwise keep desktop spacing
  local hud = state.ui._hudBounds
  local baseY
  if handheld and hud then
    -- Prefer right of HUD in handheld
    local spacing = 8
    baseX = hud.x + hud.w + spacing
    baseY = hud.y
    -- Constrain width to available space, avoiding minimap if present
    local mm = state.ui._miniMap
    local rightMargin = 16
    local maxRight = screenW - rightMargin
    if mm then maxRight = math.min(maxRight, mm.x - spacing) end
    -- If not enough horizontal space, fall back to below HUD
    if baseX + 120 > maxRight then
      baseX = 16
      baseY = hud.y + hud.h + 6
    end
  else
    baseY = (handheld and 96 or 128)
  end
  -- Compute prompt width to fit available space
  local rightLimit = screenW - 16
  local mm = state.ui._miniMap
  if handheld and mm and baseY >= (state.ui._hudBounds and state.ui._hudBounds.y or 0) and baseX < mm.x then
    rightLimit = math.min(rightLimit, mm.x - 8)
  end
  local w = math.min(handheld and 360 or 520, rightLimit - baseX)
  local h = handheld and 42 or 56
  local spacing = 8
  local y = baseY
  for i, p in ipairs(list) do
    local t = p.t or 0
    local dur = p.duration or 0
    local alpha = 1.0
    if dur > 0 and dur < 9000 then
      local remain = math.max(0, dur - t)
      alpha = math.min(1, remain / (dur * 0.5))
    end
    -- Parchment theme like objectives
    drawParchmentPanel(baseX, y, w, h)
    love.graphics.setColor(0.18, 0.11, 0.06, alpha)
    if handheld then pushTinyFont() end
    love.graphics.printf(p.text or '', baseX + 12, y + (handheld and 10 or 16), w - 24, 'left')
    if handheld then popUIFont() end
    y = y + h + spacing
  end
end

function ui.drawWheelMenu(state)
  if not state.ui._wheelMenuActive or not state.ui._handheldMode then return end
  
  local screenW, screenH = love.graphics.getDimensions()
  local centerX, centerY = screenW / 2, screenH / 2
  
  -- Dim background
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)
  
  local opts = ui.buildMenu.options or {}
  local count = #opts
  if count == 0 then return end
  
  -- Layout numbers
  local radius = 130
  local itemRadius = 26
  local angleStep = (2 * math.pi) / count
  
  -- Decorative outer ring
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle('fill', centerX + 3, centerY + 4, radius + 42)
  love.graphics.setColor(0.92, 0.80, 0.58, 1.0)
  love.graphics.setLineWidth(3)
  love.graphics.circle('line', centerX, centerY, radius + 40)
  love.graphics.setLineWidth(1)
  -- Tick marks for each slice
  for i = 1, count do
    local ang = (i - 1) * angleStep - math.pi / 2
    local tx1 = centerX + math.cos(ang) * (radius + 34)
    local ty1 = centerY + math.sin(ang) * (radius + 34)
    local tx2 = centerX + math.cos(ang) * (radius + 46)
    local ty2 = centerY + math.sin(ang) * (radius + 46)
    love.graphics.setColor(0.65, 0.46, 0.24, 1.0)
    love.graphics.setLineWidth(2)
    love.graphics.line(tx1, ty1, tx2, ty2)
    love.graphics.setLineWidth(1)
  end
  
  -- Spokes and items
  local selIdx = state.ui._wheelMenuSelection or 0
  for i, opt in ipairs(opts) do
    local angle = (i - 1) * angleStep - math.pi / 2  -- Start from top
    local x = centerX + math.cos(angle) * radius
    local y = centerY + math.sin(angle) * radius
    
    -- Spoke
    love.graphics.setColor(0.18, 0.11, 0.06, 0.25)
    love.graphics.setLineWidth(2)
    love.graphics.line(centerX, centerY, x, y)
    love.graphics.setLineWidth(1)

    local isSelected = (selIdx == i)

    -- Shadow/glow behind item
    if isSelected then
      local pulse = 0.25 + 0.25 * math.sin(love.timer.getTime() * 6)
      love.graphics.setColor(0.95, 0.90, 0.45, 0.55 + pulse)
      love.graphics.circle('fill', x, y, itemRadius + 10)
      love.graphics.setColor(0.20, 0.78, 0.30, 0.75)
      love.graphics.setLineWidth(4)
      love.graphics.circle('line', x, y, itemRadius + 12)
      love.graphics.setLineWidth(1)
    else
      love.graphics.setColor(0, 0, 0, 0.20)
      love.graphics.circle('fill', x + 2, y + 3, itemRadius + 6)
    end

    -- Item button plate
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.circle('fill', x, y, itemRadius)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.circle('fill', x, y, itemRadius - 2)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.circle('line', x, y, itemRadius - 2)
    
    -- Item icon surface
    love.graphics.setColor(opt.color or {0.5, 0.5, 0.5, 1.0})
    love.graphics.circle('fill', x, y, itemRadius - 8)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.circle('line', x, y, itemRadius - 8)
    
    -- Draw building icon inside
    love.graphics.push()
    love.graphics.translate(x, y)
    local scale = isSelected and 0.70 or 0.60
    love.graphics.scale(scale, scale)
    buildings.drawIcon(opt.key, 0, 0, (itemRadius - 8) * 1.8, 0)
    love.graphics.pop()
    
    -- No per-item label (only selected name will be shown separately)
  end
  
  -- Center hub
  love.graphics.setColor(0.32, 0.20, 0.10, 1.0)
  love.graphics.circle('fill', centerX + 2, centerY + 3, 22)
  love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
  love.graphics.circle('fill', centerX, centerY, 20)
  love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
  love.graphics.circle('line', centerX, centerY, 20)

  -- Pointer arrow towards current selection
  if selIdx and selIdx > 0 then
    local ang = (selIdx - 1) * angleStep - math.pi / 2
    local px = centerX + math.cos(ang) * (radius - 24)
    local py = centerY + math.sin(ang) * (radius - 24)
    local left = ang + math.pi * 0.5
    local right = ang - math.pi * 0.5
    love.graphics.setColor(0.20, 0.78, 0.30, 0.9)
    love.graphics.polygon('fill',
      px, py,
      centerX + math.cos(left) * 12, centerY + math.sin(left) * 12,
      centerX + math.cos(right) * 12, centerY + math.sin(right) * 12
    )
  end

  -- Selected label only
  if selIdx and selIdx > 0 then
    local label = opts[selIdx] and opts[selIdx].label or ''
    if opts[selIdx] and opts[selIdx].key == 'road' then label = 'Road' end
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle('fill', centerX - 140 + 3, centerY + radius + 20 + 3, 280, 34, 8, 8)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', centerX - 140, centerY + radius + 20, 280, 34, 8, 8)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle('line', centerX - 140, centerY + radius + 20, 280, 34, 8, 8)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf(label, centerX - 140, centerY + radius + 26, 280, 'center')
  end
end

function ui.drawPauseMenu(state)
  if not state.ui.isPaused then return end
  -- Do not show pause menu while Food Panel is open
  if state.ui.isFoodPanelOpen then return end
  local screenW, screenH = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)

  local contentHeight = #ui.pauseMenu.options * ui.pauseMenu.optionHeight + (#ui.pauseMenu.options - 1) * ui.pauseMenu.optionSpacing
  local panelW = ui.pauseMenu.width
  local panelH = contentHeight + 40
  local panelX = (screenW - panelW) / 2
  local panelY = (screenH - panelH) / 2

  drawParchmentPanel(panelX, panelY, panelW, panelH)

  local ox = panelX + 20
  local oy = panelY + 20
  for i, opt in ipairs(ui.pauseMenu.options) do
    local btnY = oy + (i - 1) * (ui.pauseMenu.optionHeight + ui.pauseMenu.optionSpacing)
    local btnW = panelW - 40
    local btnH = ui.pauseMenu.optionHeight
    local mx, my = ui.getPointer()
    local hovered = utils.isPointInRect(mx, my, ox, btnY, btnW, btnH)
    local focused = (state.ui._pauseMenuFocus == i)
    if hovered or focused then
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', ox - 2, btnY + 2, btnW + 4, btnH + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', ox, btnY, btnW, btnH, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', ox, btnY, btnW, btnH, 8, 8)
      -- Add more prominent focus highlighting for handheld mode
      if focused and state.ui._handheldMode then
        love.graphics.setColor(0.20, 0.78, 0.30, 0.25)
        love.graphics.rectangle('fill', ox + 3, btnY + 3, btnW - 6, btnH - 6, 6, 6)
      end
    else
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', ox - 2, btnY + 2, btnW + 4, btnH + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', ox, btnY, btnW, btnH, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', ox, btnY, btnW, btnH, 8, 8)
    end
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf(opt.label, ox, btnY + 12, btnW, "center")
    opt._bounds = { x = ox, y = btnY, w = btnW, h = btnH }
  end

  -- Save/Load slot dialog overlay
  if state.ui._saveLoadMode then
    local title = state.ui._saveLoadMode == 'save' and 'Select save slot' or 'Select load slot'
    local w, h = 360, 240
    local x = (screenW - w) / 2
    local y = (screenH - h) / 2
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
    drawParchmentPanel(x, y, w, h)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf(title, x, y + 14, w, 'center')

    local btns = {}
    local btnW, btnH = w - 40, 40
    local bx = x + 20
    local by = y + 60
    for slot = 1, 3 do
      local exists = love.filesystem.getInfo(string.format('save_%d.json', slot)) ~= nil
      local mx, my = ui.getPointer()
      local hovered = utils.isPointInRect(mx, my, bx, by, btnW, btnH)
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', bx - 2, by + 2, btnW + 4, btnH + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', bx, by, btnW, btnH, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', bx, by, btnW, btnH, 8, 8)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      local label = exists and string.format('Slot %d  (occupied)', slot) or string.format('Slot %d  (empty)', slot)
      love.graphics.printf(label, bx, by + 10, btnW, 'center')
      table.insert(btns, { x = bx, y = by, w = btnW, h = btnH, slot = slot })
      by = by + btnH + 10
    end
    -- Cancel button
    local hx, hy = ui.getPointer()
    local hovered = utils.isPointInRect(hx, hy, bx, y + h - 20 - btnH, btnW, btnH)
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.rectangle('fill', bx - 2, y + h - 20 - btnH + 2, btnW + 4, btnH + 4, 8, 8)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle('fill', bx, y + h - 20 - btnH, btnW, btnH, 8, 8)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle('line', bx, y + h - 20 - btnH, btnW, btnH, 8, 8)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.printf('Cancel', bx, y + h - 20 - btnH + 10, btnW, 'center')
    table.insert(btns, { x = bx, y = y + h - 20 - btnH, w = btnW, h = btnH, cancel = true })

    state.ui._saveLoadButtons = btns
  else
    state.ui._saveLoadButtons = nil
  end
end

function ui.drawSelectedPanel(state)
  local sel = state.ui.selectedBuilding
  if not sel then return end
  local mx, my = 16, love.graphics.getHeight() - 140
  local panelW, panelH = 380, 120
  drawParchmentPanel(mx, my, panelW, panelH)

  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print(string.format('%s', sel.type), mx + 12, my + 12)
  love.graphics.print(string.format('Location: (%d,%d)', sel.tileX, sel.tileY), mx + 12, my + 30)
  if sel.construction and not sel.construction.complete and sel.construction.waitingForResources then
    love.graphics.setColor(0.95, 0.7, 0.2, 1)
    love.graphics.print('Planned: waiting for resources', mx + 160, my + 12)
  end
  if sel.id then
    local pos, total, prio
    total = #(state.game.buildQueue or {})
    for i, q in ipairs(state.game.buildQueue or {}) do
      if q.id == sel.id then pos = i; prio = q.priority or 0; break end
    end
    if pos then
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(string.format('Queue: #%d / %d  (priority %d)', pos, total, prio or 0), mx + 12, my + 92)
      -- simple priority up/down buttons
      local btnW, btnH = 24, 20
      local upx, upy = mx + 250, my + 88
      local dnx, dny = upx + btnW + 6, upy
      love.graphics.setColor(0.35,0.22,0.12,1.0)
      love.graphics.rectangle('fill', upx-2, upy+2, btnW+4, btnH+4, 6, 6)
      love.graphics.setColor(0.95,0.82,0.60,1.0)
      love.graphics.rectangle('fill', upx, upy, btnW, btnH, 6, 6)
      love.graphics.setColor(0.78,0.54,0.34,1.0)
      love.graphics.rectangle('line', upx, upy, btnW, btnH, 6, 6)
      love.graphics.setColor(0.18,0.11,0.06,1.0)
      love.graphics.printf('^', upx, upy + 2, btnW, 'center')
      love.graphics.setColor(0.35,0.22,0.12,1.0)
      love.graphics.rectangle('fill', dnx-2, dny+2, btnW+4, btnH+4, 6, 6)
      love.graphics.setColor(0.95,0.82,0.60,1.0)
      love.graphics.rectangle('fill', dnx, dny, btnW, btnH, 6, 6)
      love.graphics.setColor(0.78,0.54,0.34,1.0)
      love.graphics.rectangle('line', dnx, dny, btnW, btnH, 6, 6)
      love.graphics.setColor(0.18,0.11,0.06,1.0)
      love.graphics.printf('v', dnx, dny + 2, btnW, 'center')
      sel._queueUpBtn = { x = upx, y = upy, w = btnW, h = btnH }
      sel._queueDownBtn = { x = dnx, y = dny, w = btnW, h = btnH }
    end
  end

  -- staffing controls if applicable
  sel._assignBtn, sel._unassignBtn = nil, nil
  if sel.type == 'lumberyard' or sel.type == 'builder' then
    local maxSlots = (sel.type == 'lumberyard') and (state.buildingDefs.lumberyard.numWorkers or 0) or (state.buildingDefs.builder.numWorkers or 0)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(string.format('Workers: %d / %d', sel.assigned or 0, maxSlots), mx + 12, my + 48)
    local btnW, btnH = 28, 24
    local remX, remY = mx + 180, my + 44
    local addX, addY = remX + btnW + 6, remY
    love.graphics.setColor(0.35,0.22,0.12,1.0)
    love.graphics.rectangle('fill', remX-2, remY+2, btnW+4, btnH+4, 6, 6)
    love.graphics.setColor(0.95,0.82,0.60,1.0)
    love.graphics.rectangle('fill', remX, remY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78,0.54,0.34,1.0)
    love.graphics.rectangle('line', remX, remY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.18,0.11,0.06,1.0)
    love.graphics.printf('-', remX, remY + 4, btnW, 'center')
    love.graphics.setColor(0.35,0.22,0.12,1.0)
    love.graphics.rectangle('fill', addX-2, addY+2, btnW+4, btnH+4, 6, 6)
    love.graphics.setColor(0.95,0.82,0.60,1.0)
    love.graphics.rectangle('fill', addX, addY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78,0.54,0.34,1.0)
    love.graphics.rectangle('line', addX, addY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.18,0.11,0.06,1.0)
    love.graphics.printf('+', addX, addY + 4, btnW, 'center')
    sel._unassignBtn = { x = remX, y = remY, w = btnW, h = btnH }
    sel._assignBtn = { x = addX, y = addY, w = btnW, h = btnH }
  elseif sel.type == 'farm' then
    local maxSlots = state.buildingDefs.farm.numWorkers or 0
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(string.format('Workers: %d / %d', sel.assigned or 0, maxSlots), mx + 12, my + 48)
    local btnW, btnH = 28, 24
    local remX, remY = mx + 180, my + 44
    local addX, addY = remX + btnW + 6, remY
    love.graphics.setColor(0.35,0.22,0.12,1.0)
    love.graphics.rectangle('fill', remX-2, remY+2, btnW+4, btnH+4, 6, 6)
    love.graphics.setColor(0.95,0.82,0.60,1.0)
    love.graphics.rectangle('fill', remX, remY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78,0.54,0.34,1.0)
    love.graphics.rectangle('line', remX, remY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.18,0.11,0.06,1.0)
    love.graphics.printf('-', remX, remY + 4, btnW, 'center')
    love.graphics.setColor(0.35,0.22,0.12,1.0)
    love.graphics.rectangle('fill', addX-2, addY+2, btnW+4, btnH+4, 6, 6)
    love.graphics.setColor(0.95,0.82,0.60,1.0)
    love.graphics.rectangle('fill', addX, addY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78,0.54,0.34,1.0)
    love.graphics.rectangle('line', addX, addY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.18,0.11,0.06,1.0)
    love.graphics.printf('+', addX, addY + 4, btnW, 'center')
    sel._unassignBtn = { x = remX, y = remY, w = btnW, h = btnH }
    sel._assignBtn = { x = addX, y = addY, w = btnW, h = btnH }
  elseif sel.type == 'research' then
    local maxSlots = state.buildingDefs.research.numWorkers or 0
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(string.format('Researchers: %d / %d', sel.assigned or 0, maxSlots), mx + 12, my + 48)
    local btnW, btnH = 28, 24
    local remX, remY = mx + 220, my + 44
    local addX, addY = remX + btnW + 6, remY
    love.graphics.setColor(0.35,0.22,0.12,1.0)
    love.graphics.rectangle('fill', remX-2, remY+2, btnW+4, btnH+4, 6, 6)
    love.graphics.setColor(0.95,0.82,0.60,1.0)
    love.graphics.rectangle('fill', remX, remY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78,0.54,0.34,1.0)
    love.graphics.rectangle('line', remX, remY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.18,0.11,0.06,1.0)
    love.graphics.printf('-', remX, remY + 4, btnW, 'center')
    love.graphics.setColor(0.35,0.22,0.12,1.0)
    love.graphics.rectangle('fill', addX-2, addY+2, btnW+4, btnH+4, 6, 6)
    love.graphics.setColor(0.95,0.82,0.60,1.0)
    love.graphics.rectangle('fill', addX, addY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.78,0.54,0.34,1.0)
    love.graphics.rectangle('line', addX, addY, btnW, btnH, 6, 6)
    love.graphics.setColor(0.18,0.11,0.06,1.0)
    love.graphics.printf('+', addX, addY + 4, btnW, 'center')
    sel._unassignBtn = { x = remX, y = remY, w = btnW, h = btnH }
    sel._assignBtn = { x = addX, y = addY, w = btnW, h = btnH }
  elseif sel.type == 'market' then
    local pop = state.game.population.total or 0
    local stock = (sel.storage and sel.storage.food) or 0
    local demand = pop
    local deficit = math.max(0, demand - stock)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(string.format('Stock: %d food', stock), mx + 12, my + 48)
    love.graphics.print(string.format("Tonight's demand: %d", demand), mx + 12, my + 68)
    if deficit > 0 then
      love.graphics.setColor(0.72, 0.2, 0.16, 1)
      love.graphics.print(string.format('Deficit: %d (villagers will starve)', deficit), mx + 12, my + 88)
    else
      love.graphics.setColor(0.20, 0.6, 0.25, 1)
      love.graphics.print('Ready for dinner', mx + 12, my + 88)
    end
  end

  -- Demolish button
  local btnW, btnH = 100, 28
  local bx, by = mx + panelW - btnW - 12, my + panelH - btnH - 12
  love.graphics.setColor(0.35,0.22,0.12,1.0)
  love.graphics.rectangle('fill', bx-2, by+2, btnW+4, btnH+4, 6, 6)
  love.graphics.setColor(0.95,0.82,0.60,1.0)
  love.graphics.rectangle('fill', bx, by, btnW, btnH, 6, 6)
  love.graphics.setColor(0.78,0.54,0.34,1.0)
  love.graphics.rectangle('line', bx, by, btnW, btnH, 6, 6)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.printf('Demolish', bx, by + 6, btnW, 'center')
  sel._demolishBtn = { x = bx, y = by, w = btnW, h = btnH }
end

function ui.drawControlsOverlay(state)
  if not state.ui._handheldMode or not state.ui._controlsOverlayOpen then return end
  local screenW, screenH = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle('fill', 0, 0, screenW, screenH)

  local w, h = 520, 360
  local x, y = (screenW - w) / 2, (screenH - h) / 2
  drawParchmentPanel(x, y, w, h)

  local line = y + 16
  local function printRow(label)
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print(label, x + 16, line)
    line = line + 26
  end

  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print('Handheld Controls', x + 16, line)
  line = line + 32

  -- Buttons
  printRow('A: Confirm / Select')
  printRow('B: Cancel / Secondary click')
  printRow('X: Toggle this controls overlay')
  printRow('Start: Toggle Pause Menu')
  printRow('L2: Cycle Game Speed (1x,2x,4x,8x)')
  printRow('R2: Hold for Build Wheel; release to select')

  line = line + 12
  printRow('D-Pad Up: Toggle Build Queue')
  printRow('D-Pad Down: Toggle Villagers Panel')

  line = line + 12
  printRow('Left Stick: Move camera cursor (when no menu/wheel is open)')
  printRow('Left Stick (in Wheel): Point to select; neutral centers')

  love.graphics.setColor(0.18, 0.11, 0.06, 0.75)
  love.graphics.printf('Press X again to close', x, y + h - 28, w, 'center')
end

return ui 