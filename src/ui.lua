-- ui.lua
-- UI elements: build button, build menu, HUD, pause menu

local constants = require('src.constants')
local utils = require('src.utils')
local colors = constants.colors
local buildings = require('src.buildings')

local ui = {}

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
    { key = "research", label = "Research Center", color = { 0.5, 0.6, 0.9, 1.0 } }
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
    local mx, my = love.mouse.getPosition()
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
  for index, option in ipairs(m.options) do
    local ox = x + 12
    local oy = y + 12 + (index - 1) * (optionHeight + 8)
    local ow = w - 24
    local oh = optionHeight
    local mx, my = love.mouse.getPosition()
    local hovered = utils.isPointInRect(mx, my, ox, oy, ow, oh)

    -- parchment-style option row
    love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
    love.graphics.rectangle('fill', ox - 2, oy + 2, ow + 4, oh + 4, 6, 6)
    love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
    love.graphics.rectangle("fill", ox, oy, ow, oh, 6, 6)
    love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
    love.graphics.rectangle("line", ox, oy, ow, oh, 6, 6)
    if hovered then
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
    local def = buildingDefs[option.key]
    local costText = ""
    if def and def.cost and def.cost.wood then
      costText = string.format(" (Cost: %d wood)", def.cost.wood)
    end
    love.graphics.print(option.label .. costText, ox + 52, oy + 12)

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

  local w, h = 520, 200
  local screenW, screenH = love.graphics.getDimensions()
  local x = (screenW - w) / 2
  local y = (screenH - h) / 2
  drawParchmentPanel(x, y, w, h)

  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  local pop = state.game.population
  love.graphics.print(string.format('Villagers: %d / %d assigned', pop.assigned or 0, pop.total or 0), x + 12, y + 12)
  love.graphics.print(string.format('Capacity: %d', pop.capacity or 0), x + 12, y + 32)

  local btns = {}
  local rowY = y + 64
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'lumberyard' or b.type == 'builder' or b.type == 'farm' or b.type == 'research' then
      local name = (b.type == 'lumberyard') and 'Lumberyard' or (b.type == 'builder' and 'Builders Workplace' or (b.type == 'farm' and 'Farm' or 'Research Center'))
      local maxSlots = (b.type == 'lumberyard') and (state.buildingDefs.lumberyard.numWorkers or 0)
        or (b.type == 'builder' and (state.buildingDefs.builder.numWorkers or 0)
        or (b.type == 'farm' and (state.buildingDefs.farm.numWorkers or 0) or (state.buildingDefs.research.numWorkers or 0)))
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(string.format('%s (%d/%d)  Location: (%d,%d)', name, b.assigned or 0, maxSlots, b.tileX, b.tileY), x + 12, rowY)
      local btnW, btnH = 28, 24
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
      rowY = rowY + 28
    end
  end
  state.ui._villagersPanelButtons = btns
end

function ui.drawBuildQueue(state)
  if not state.ui.isBuildQueueOpen then return end
  local screenW, screenH = love.graphics.getDimensions()
  local w, h = 560, 260
  -- Always center the panel in the middle of the screen
  local x = (screenW - w) / 2
  local y = (screenH - h) / 2
  drawParchmentPanel(x, y, w, h)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print('Build Queue', x + 12, y + 12)
  local headerY = y + 36
  local rowH = 34
  local btnW, btnH = 24, 20
  state.ui._queueButtons = {}
  state.ui._queueHoverId = nil
  state.ui._queueLayout = { headerY = headerY, rowH = rowH, x = x, y = y, w = w, h = h }
  local byId = {}
  for _, b in ipairs(state.game.buildings) do byId[b.id] = b end
  local qraw = state.game.buildQueue or {}
  if #qraw == 0 then
    love.graphics.setColor(colors.text)
    love.graphics.print('Queue is empty. Place buildings to add plans here.', x + 12, headerY)
    return
  end
  -- draw in current queue order; top is highest priority
  local drag = state.ui._queueDrag
  local mx, my = love.mouse.getPosition()
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
        love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
        love.graphics.rectangle('fill', rowRect.x - 2, rowRect.y + 2, rowRect.w + 4, rowRect.h + 4, 6, 6)
        love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
        love.graphics.rectangle('fill', rowRect.x, rowRect.y, rowRect.w, rowRect.h, 6, 6)
        love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
        love.graphics.rectangle('line', rowRect.x, rowRect.y, rowRect.w, rowRect.h, 6, 6)
        if hovered then love.graphics.setColor(0.20, 0.78, 0.30, 0.12); love.graphics.rectangle('fill', rowRect.x+2, rowRect.y+2, rowRect.w-4, rowRect.h-4, 4, 4) end
        love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
        -- icon
        buildings.drawIcon(b.type, x + 18, ry + (rowH/2), 24, 0)
        -- name + coords
        local status
        if b.construction and b.construction.complete then status = 'Complete'
        elseif b.construction and b.construction.waitingForResources then status = 'Waiting'
        elseif b._claimedBy then status = 'Building…' else status = 'Ready' end
        love.graphics.print(string.format('%s  (%d,%d)  [%s]', b.type, b.tileX, b.tileY, status), x + 44, ry + 8)
        -- priority up/down
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
        -- pause/resume
        local px = x + w - 140; local py = upy
        local label = (q.paused and 'Resume') or 'Pause'
        local pw = 64
        love.graphics.setColor(0.35,0.22,0.12,1.0)
        love.graphics.rectangle('fill', px-2, py+2, pw+4, btnH+4, 6, 6)
        love.graphics.setColor(0.95,0.82,0.60,1.0)
        love.graphics.rectangle('fill', px, py, pw, btnH, 6, 6)
        love.graphics.setColor(0.78,0.54,0.34,1.0)
        love.graphics.rectangle('line', px, py, pw, btnH, 6, 6)
        love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
        love.graphics.printf(label, px, py + 2, pw, 'center')
        -- remove
        local rx = x + w - 70; local ryb = upy
        love.graphics.setColor(0.35,0.22,0.12,1.0)
        love.graphics.rectangle('fill', rx-2, ryb+2, 60+4, btnH+4, 6, 6)
        love.graphics.setColor(0.90, 0.35, 0.25, 1.0)
        love.graphics.rectangle('fill', rx, ryb, 60, btnH, 6, 6)
        love.graphics.setColor(0.78,0.54,0.34,1.0)
        love.graphics.rectangle('line', rx, ryb, 60, btnH, 6, 6)
        love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
        love.graphics.printf('Remove', rx, ryb + 2, 60, 'center')

        state.ui._queueButtons[#state.ui._queueButtons + 1] = {
          id = b.id,
          row = i,
          up = { x = upx, y = upy, w = btnW, h = btnH },
          down = { x = dnx, y = dny, w = btnW, h = btnH },
          pause = { x = px, y = py, w = pw, h = btnH },
          remove = { x = rx, y = ryb, w = 60, h = btnH },
          rowRect = rowRect
        }
      end
      -- compute tentative drop index while dragging
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
    -- draw floating row at mouse
    local floatY = my - (drag.offsetY or 0)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle('fill', x + 8, floatY, w - 16, rowH - 4, 6, 6)
    love.graphics.setColor(colors.text)
    local b = nil
    for _, bb in ipairs(state.game.buildings) do if bb.id == drag.id then b = bb; break end end
    if b then
      buildings.drawIcon(b.type, x + 18, floatY + (rowH/2), 24, 0)
      local status
      if b.construction and b.construction.complete then status = 'Complete'
      elseif b.construction and b.construction.waitingForResources then status = 'Waiting'
      elseif b._claimedBy then status = 'Building…' else status = 'Ready' end
      love.graphics.print(string.format('%s  (%d,%d)  [%s]', b.type, b.tileX, b.tileY, status), x + 44, floatY + 8)
    end
  else
    state.ui._queueDropIndex = nil
  end
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
end

function ui.drawHUD(state)
  local x = ui.villagersButton.x + ui.villagersButton.width + 16
  local y = 16
  local w = 600
  local h = 100
  -- parchment theme like objectives
  drawParchmentPanel(x, y, w, h)

  love.graphics.setColor(colors.text)
  local baseWood = math.floor(state.game.resources.wood + 0.5)
  local storedWood = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      storedWood = storedWood + b.storage.wood
    end
  end
  local totalWood = baseWood + storedWood
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print(string.format("Wood: %d", totalWood), x + 12, y + 12)
  local baseFood = math.floor((state.game.resources.food or 0) + 0.5)
  local storedFood = 0
  for _, b in ipairs(state.game.buildings) do
    if (b.type == 'market' or b.type == 'builder') and b.storage and b.storage.food then
      storedFood = storedFood + b.storage.food
    end
  end
  local totalFood = baseFood + storedFood
  local foodLabel = string.format("Food: %d", totalFood)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print(foodLabel, x + 12, y + 32)
  -- clickable bounds for food
  local fw = love.graphics.getFont():getWidth(foodLabel)
  state.ui._foodButton = { x = x + 10, y = y + 30, w = fw + 6, h = 18 }

  -- Research progress (if any Research Center exists)
  do
    local hasResearch = false
    for _, b in ipairs(state.game.buildings) do if b.type == 'research' then hasResearch = true break end end
    if hasResearch then
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

  local hours = math.floor(state.time.normalized * 24) % 24
  local minutes = math.floor((state.time.normalized * 24 - hours) * 60)
  local tnorm = state.time.normalized
  local isDay = (tnorm >= 0.25 and tnorm < 0.75)
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print(string.format("Time: %02d:%02d (%s)", hours, minutes, isDay and "Day" or "Night"), x + 220, y + 12)
  love.graphics.print(string.format("Speed: %dx", state.time.speed or 1), x + 400, y + 12)

  local btnW, btnH = 36, 22
  local s1x = x + 390; local s1y = y + 52
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
  if state.ui.isDemolishMode then
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    love.graphics.print("Demolish Mode: click a building to remove (refund 50%)", x + 12, y + 60)
  end

  ui.drawVillagersPanel(state)
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
    local oy = y + 40
    for i, opt in ipairs(options) do
      local btn = { x = x + 12, y = oy, w = w - 24, h = 30, id = opt.id, label = opt.label }
      local mx, my = love.mouse.getPosition()
      local hovered = utils.isPointInRect(mx, my, btn.x, btn.y, btn.w, btn.h)
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', btn.x - 2, btn.y + 2, btn.w + 4, btn.h + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', btn.x, btn.y, btn.w, btn.h, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', btn.x, btn.y, btn.w, btn.h, 8, 8)
      if hovered then love.graphics.setColor(0.20, 0.78, 0.30, 0.18); love.graphics.rectangle('fill', btn.x+2, btn.y+2, btn.w-4, btn.h-4, 6, 6) end
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.printf(opt.label, btn.x, btn.y + 8, btn.w, 'center')
      table.insert(state.ui._missionSelectorButtons, btn)
      oy = oy + 36
    end
    return
  end
  -- Layout calculations with dynamic height and text wrapping
  local w = 420
  local padding = 12
  local titleH = 24
  local font = love.graphics.getFont()
  local lineH = font:getHeight()
  local contentH = titleH + 6
  local textW = w - 44
  -- Measure objective blocks
  for _, o in ipairs(M.objectives or {}) do
    local _, lines = font:getWrap(o.text or '', textW)
    local linesH = math.max(lineH, #lines * lineH)
    local barH = (o.target and o.target > 1) and (10 + 8) or 0
    contentH = contentH + math.max(24, linesH) + barH + 10
  end
  if M.completed then contentH = contentH + 20 end
  local h = contentH + padding * 2
  local x = love.graphics.getWidth() - w - 16
  local y = love.graphics.getHeight() - h - 16

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

  -- Title in pixel style
  love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
  love.graphics.print('MISSION: ' .. string.upper(M.name or 'Unknown'), x + 12, y + 10)

  local oy = y + 10 + titleH
  for _, o in ipairs(M.objectives or {}) do
    -- draw scroll-like strip
    local rowH = math.max(24, lineH)
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

    -- Wrapped text in uppercase for pixel feel
    love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
    local tx = sx + 22
    local tw = stripW - 44
    local text = (o.text or '')
    love.graphics.printf(text, tx, sy + 6, tw, 'left')

    -- Progress bar (pixel)
    local blockBottom = sy + rowH + 2
    if o.target and o.target > 1 then
      local bw, bh = stripW - 28, 8
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
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(string.format('%d / %d', math.floor(o.current or 0), o.target), bx + bw - 56, by - 12)
      oy = by + bh + 12
    else
      oy = blockBottom + 12
    end
  end
  if M.completed then
    love.graphics.setColor(1, 1, 0.6, 1)
    love.graphics.print('Completed!', x + 12, y + h - 22)
  end
end

function ui.drawPrompt(state)
  local list = state.ui.prompts or {}
  if #list == 0 then return end
  local screenW, screenH = love.graphics.getDimensions()
  local baseX = 16
  local baseY = 16 + 40 + 8 + 100 + 8
  local w = math.min(520, screenW - baseX - 16)
  local h = 56
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
    love.graphics.printf(p.text or '', baseX + 12, y + 16, w - 24, 'left')
    y = y + h + spacing
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
    local mx, my = love.mouse.getPosition()
    local hovered = utils.isPointInRect(mx, my, ox, btnY, btnW, btnH)
    if hovered then
      love.graphics.setColor(0.35, 0.22, 0.12, 1.0)
      love.graphics.rectangle('fill', ox - 2, btnY + 2, btnW + 4, btnH + 4, 8, 8)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', ox, btnY, btnW, btnH, 8, 8)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', ox, btnY, btnW, btnH, 8, 8)
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
      local mx, my = love.mouse.getPosition()
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
    local hovered = utils.isPointInRect(love.mouse.getX(), love.mouse.getY(), bx, y + h - 20 - btnH, btnW, btnH)
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

return ui 