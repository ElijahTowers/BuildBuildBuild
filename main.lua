-- main.lua
-- Entry point: orchestrates modules and game loop

-- Ensure LÖVE's require path can resolve modules inside 'src/' on all platforms (incl. Android)
pcall(function()
  if love and love.filesystem and love.filesystem.setRequirePath then
    local getPath = love.filesystem.getRequirePath and love.filesystem.getRequirePath or function() return '' end
    local current = getPath()
    local wanted = '?.lua;?/init.lua;src/?.lua;src/?/init.lua'
    if not current or current == '' then
      love.filesystem.setRequirePath(wanted)
    elseif not current:find('src/%?%.lua', 1, true) then
      love.filesystem.setRequirePath(wanted .. ';' .. current)
    end
  end
end)

-- Robust module aliasing: ensure both 'name' and 'src.name' resolve to the same module
local function _ensureModuleAliases(baseName)
  local rootKey = baseName
  local srcKey = 'src.' .. baseName
  if package.loaded[srcKey] and package.loaded[rootKey] then return true end

  local function tryRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod ~= true then return mod end
    return nil
  end

  local function loadFromVFS(path)
    if not (love and love.filesystem and love.filesystem.getInfo and love.filesystem.load) then return nil end
    if not love.filesystem.getInfo(path) then return nil end
    local chunk, err = love.filesystem.load(path)
    if not chunk then return nil end
    local ok, mod = pcall(chunk)
    if ok and mod ~= true then return mod end
    return nil
  end

  -- Prefer existing files if we can detect them
  if love and love.filesystem and love.filesystem.getInfo then
    if love.filesystem.getInfo('src/' .. baseName .. '.lua') then
      local mod = tryRequire(srcKey) or loadFromVFS('src/' .. baseName .. '.lua')
      if mod then
        package.loaded[srcKey] = mod
        package.loaded[rootKey] = package.loaded[rootKey] or mod
        return true
      end
    elseif love.filesystem.getInfo(baseName .. '.lua') then
      local mod = tryRequire(rootKey) or loadFromVFS(baseName .. '.lua')
      if mod then
        package.loaded[rootKey] = mod
        package.loaded[srcKey] = package.loaded[srcKey] or mod
        return true
      end
    end
  end

  -- Fallback: try both names via require
  local mod = tryRequire(srcKey) or tryRequire(rootKey)
  if mod then
    package.loaded[srcKey] = package.loaded[srcKey] or mod
    package.loaded[rootKey] = package.loaded[rootKey] or mod
    return true
  end
  return false
end

do
  local modules = {
    'constants','utils','state','trees','grid','particles','buildings','workers','ui','save','roads','missions'
  }
  for i = 1, #modules do _ensureModuleAliases(modules[i]) end
end

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
  if state.ui._handheldMode and state.ui._useVirtualCursor and state.ui._virtualCursor then
    mx, my = state.ui._virtualCursor.x or mx, state.ui._virtualCursor.y or my
  end
  -- If a gamepad stick is used, allow a virtual cursor for handhelds
  if state.ui._useVirtualCursor and state.ui._virtualCursor then mx, my = state.ui._virtualCursor.x, state.ui._virtualCursor.y end
  local worldX = state.camera.x + mx / state.camera.scale
  local worldY = state.camera.y + my / state.camera.scale
  local tileX = math.floor(worldX / TILE_SIZE)
  local tileY = math.floor(worldY / TILE_SIZE)
  return tileX, tileY
end

-- Convert explicit screen coords to tile (use for click handling to avoid drift)
local function screenToTile(sx, sy)
  if state.ui._handheldMode and state.ui._useVirtualCursor and state.ui._virtualCursor and (sx == nil or sy == nil) then
    sx, sy = state.ui._virtualCursor.x, state.ui._virtualCursor.y
  end
  local worldX = state.camera.x + (sx or 0) / state.camera.scale
  local worldY = state.camera.y + (sy or 0) / state.camera.scale
  return math.floor(worldX / TILE_SIZE), math.floor(worldY / TILE_SIZE)
end

-- Gamepad virtual cursor state
state.ui._virtualCursor = state.ui._virtualCursor or { x = 200, y = 200 }
local gamepad = nil

-- Returns true if mouse is over any UI panel (build button or build menu)
local function isOverUI(mx, my)
  if ui.isOverBuildButton(mx, my) then return true end
  local m = ui.buildMenu
  if state.ui.isBuildMenuOpen then
    -- support handheld radial bounds too
    if state.ui._handheldMode and state.ui._buildMenuBounds then
      for _, opt in ipairs(state.ui._buildMenuBounds) do
        local b = opt._bounds
        if b and utils.isPointInRect(mx, my, b.x, b.y, b.w, b.h) then return true end
      end
    else
      if utils.isPointInRect(mx, my, m.x, m.y, m.width, m.height) then
        return true
      end
    end
  end
  return false
end

-- Handheld build menu grid navigation (2 columns)
local function moveBuildMenuFocus(dx, dy)
  local ui_mod = require('src.ui')
  local opts = ui_mod.buildMenu.options or {}
  local count = #opts
  if count == 0 then return end
  local cols = 2
  local idx = state.ui._buildMenuFocus or 1
  local col = (idx - 1) % cols
  local row = math.floor((idx - 1) / cols)

  if dy and dy ~= 0 then
    local new = idx + dy * cols
    if new >= 1 and new <= count then
      state.ui._buildMenuFocus = new
      return
    end
  end

  if dx and dx ~= 0 then
    if dx < 0 and col > 0 then
      state.ui._buildMenuFocus = idx - 1
    elseif dx > 0 and col < (cols - 1) and (idx + 1) <= count then
      state.ui._buildMenuFocus = idx + 1
    end
  end
end

-- Handheld pause menu navigation (single column)
local function movePauseMenuFocus(dy)
  local ui_mod = require('src.ui')
  local opts = ui_mod.pauseMenu.options or {}
  local count = #opts
  if count == 0 then return end
  
  local idx = state.ui._pauseMenuFocus or 1
  
  if dy and dy ~= 0 then
    local new = idx + dy
    if new >= 1 and new <= count then
      state.ui._pauseMenuFocus = new
      return
    end
  end
end

-- Apply startup preset and initialize world
local function startGameWithPreset(preset)
  local ww, wh, flags = love.window.getMode()
  flags = flags or {}
  if preset == 'retroid' then
    -- Retroid Pocket 4 Pro landscape resolution
    flags.highdpi = false
    flags.resizable = false
    flags.fullscreen = false
    flags.borderless = false
    -- Ensure we leave any fullscreen/maximized state first
    pcall(love.window.setFullscreen, false)
    pcall(love.window.restore)
    love.window.setMode(1334, 750, flags)
    -- Center the window on the primary display if possible
    if love.window.getDesktopDimensions then
      local dw, dh = love.window.getDesktopDimensions(1)
      if dw and dh and love.window.setPosition then
        local px = math.max(0, math.floor((dw - 1334) / 2))
        local py = math.max(0, math.floor((dh - 750) / 2))
        pcall(love.window.setPosition, px, py, 1)
      end
    end
    state.ui._useVirtualCursor = true
    state.ui._forceSmallScreen = true
    state.ui._handheldMode = true
    state.ui.showMinimap = true
  end
  -- Compute tiles and UI, then reset world and generate
  state.resetWorldTilesFromScreen()
  ui.computeBuildMenuHeight()
  state.restart()
  trees.generate(state)
  missions.init(state)
  -- Close startup choice
  state.ui._startupChoiceOpen = false
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

  -- Show radius while previewing for buildings with area effects
  if state.ui.selectedBuildingType == 'lumberyard' or state.ui.selectedBuildingType == 'market' or state.ui.selectedBuildingType == 'flowerbed' then
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
  if not state.ui._startupChoiceOpen then
    trees.generate(state)
    missions.init(state)
  end
 
  -- Start at beginning of the day (around sunrise ~06:00)
  state.time.t = state.time.dayLength * 0.25
  state.time.normalized = state.time.t / state.time.dayLength

  -- Start with free builder placement preview if not waiting for startup choice
  if not state.ui._startupChoiceOpen then
    state.ui.isPlacingBuilding = true
    state.ui.selectedBuildingType = 'builder'
    state.ui._isFreeInitialBuilder = true
    state.ui._pauseTimeForInitial = true
    state.ui.promptText = "Place your Builders Workplace for free. Left-click a tile to place."
    state.ui.promptT = 0
    state.ui.promptDuration = 9999
  end
end

function love.update(dt)
  if state.ui._startupChoiceOpen then return end
  -- Allow time to flow even with panels if desired; keep original pause behavior
  -- Handheld: hide virtual cursor when a navigable panel/menu is open; show it again when closed
  if state.ui._handheldMode then
    local navigableOpen = state.ui.isBuildMenuOpen == true
      or state.ui.isMissionSelectorOpen == true
      or state.ui.isVillagersPanelOpen == true
      or state.ui.isBuildQueueOpen == true
      or state.ui.isFoodPanelOpen == true
      or state.ui.isPaused == true
      or state.ui._wheelMenuActive == true
      or state.ui._controlsOverlayOpen == true
    if navigableOpen then
      state.ui._useVirtualCursor = false
    else
      state.ui._useVirtualCursor = true
    end
    
      -- Track stick state for discrete movement
  state.ui._lastStickState = state.ui._lastStickState or { x = 0, y = 0 }
  
  -- Track last D-pad axis values for edge detection (handheld)
  state.ui._lastDpadAxis = state.ui._lastDpadAxis or { up = 0, down = 0, left = 0 }
  
  -- Wheel menu state for retroid mode
  state.ui._wheelMenuActive = state.ui._wheelMenuActive or false
  state.ui._wheelMenuSelection = state.ui._wheelMenuSelection or 1
  end
  if state.ui.isPaused then return end
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

  -- Apply smooth zoom from right stick on handheld
  if state.ui._handheldMode and state.ui._zoomVel and math.abs(state.ui._zoomVel) > 1e-3 then
    local oldScale = state.camera.scale
    local newScale = utils.clamp(oldScale * (1 + state.ui._zoomVel * dt), state.camera.minScale, state.camera.maxScale)
    if math.abs(newScale - oldScale) > 1e-6 then
      local mx = love.graphics.getWidth()/2
      local my = love.graphics.getHeight()/2
      local preWorldX = state.camera.x + mx / oldScale
      local preWorldY = state.camera.y + my / oldScale
      state.camera.scale = newScale
      state.camera.x = utils.clamp(preWorldX - mx / newScale, 0, math.max(0, state.world.tilesX * TILE_SIZE - love.graphics.getWidth() / newScale))
      state.camera.y = utils.clamp(preWorldY - my / newScale, 0, math.max(0, state.world.tilesY * TILE_SIZE - love.graphics.getHeight() / newScale))
    end
    -- friction
    state.ui._zoomVel = state.ui._zoomVel * 0.9
    if math.abs(state.ui._zoomVel) < 1e-3 then state.ui._zoomVel = 0 end
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
  -- Use game-time delta so mission timers ("full day") respect time speed
  missions.update(state, sdt)
  if not isInitial then
    workers.update(state, sdt)
  end
  buildings.update(state, sdt)
  particles.update(state.game.particles, sdt)
  trees.updateShake(state, sdt)
  roads.update(state, sdt)

  -- Preview timer for pulsing outline
  state.ui.previewT = state.ui.previewT + sdt
  -- Virtual cursor update (left stick moves cursor) - disabled while navigable menu is open in handheld mode
  if gamepad and gamepad:isConnected() == false then gamepad = nil end
  if (not gamepad) and love.joystick and love.joystick.getJoysticks then
    local joys = love.joystick.getJoysticks()
    if joys and #joys > 0 then gamepad = joys[1] end
  end
  if gamepad and gamepad:isConnected() then
    local ax = gamepad:getGamepadAxis("leftx") or 0
    local ay = gamepad:getGamepadAxis("lefty") or 0
    
    -- Discrete menu navigation in handheld mode (works even when virtual cursor is suppressed)
    if state.ui._handheldMode then
      local lastX, lastY = state.ui._lastStickState.x, state.ui._lastStickState.y
      local threshold = 0.5
      
              -- Check for discrete movement (stick crosses threshold) - only when wheel menu is not active
        if not state.ui._wheelMenuActive and math.abs(ax) > threshold and math.abs(lastX) <= threshold then
          if ax > 0 then
            -- Right movement
            if state.ui.isBuildMenuOpen then
              moveBuildMenuFocus(1, 0)
            end
          else
            -- Left movement
            if state.ui.isBuildMenuOpen then
              moveBuildMenuFocus(-1, 0)
            end
          end
        end
      
      -- Wheel menu directional control (when active, disable other stick functions)
      if state.ui._wheelMenuActive then
        local ui_mod = require('src.ui')
        local opts = ui_mod.buildMenu.options or {}
        local count = #opts
        if count > 0 then
          -- Add deadzone to prevent accidental selections
          local stickMagnitude = math.sqrt(ax * ax + ay * ay)
          if stickMagnitude > 0.2 then
            -- Calculate angle from stick position
            local angle = math.atan2(ay, ax)
            -- Convert angle to selection (0 = top, clockwise)
            local normalizedAngle = (angle + math.pi / 2) % (2 * math.pi)
            local selection = math.floor((normalizedAngle / (2 * math.pi)) * count) + 1
            selection = math.max(1, math.min(count, selection))
            state.ui._wheelMenuSelection = selection
          else
            -- Return to neutral center when stick is released
            state.ui._wheelMenuSelection = 0
          end
        end
      else
        -- Normal discrete navigation when wheel menu is not active
        if math.abs(ay) > threshold and math.abs(lastY) <= threshold then
          if ay > 0 then
            -- Down movement
            if state.ui.isBuildMenuOpen then
              moveBuildMenuFocus(0, 1)
            elseif state.ui.isPaused then
              movePauseMenuFocus(1)
            elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
              local count = #(state.ui._missionSelectorButtons or {})
              local idx = (state.ui._missionSelectorFocus or 1)
              if idx < count then state.ui._missionSelectorFocus = idx + 1 end
            elseif state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
              local count = #(state.ui._villagersPanelButtons or {})
              state.ui._villagersPanelFocus = math.min(count, (state.ui._villagersPanelFocus or 1) + 1)
            elseif state.ui.isBuildQueueOpen then
              local count = #(state.game.buildQueue or {})
              state.ui._queueFocusIndex = math.min(count, (state.ui._queueFocusIndex or 1) + 1)
            end
          else
            -- Up movement
            if state.ui.isBuildMenuOpen then
              moveBuildMenuFocus(0, -1)
            elseif state.ui.isPaused then
              movePauseMenuFocus(-1)
            elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
              local idx = (state.ui._missionSelectorFocus or 1)
              if idx > 1 then state.ui._missionSelectorFocus = idx - 1 end
            elseif state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
              state.ui._villagersPanelFocus = math.max(1, (state.ui._villagersPanelFocus or 1) - 1)
            elseif state.ui.isBuildQueueOpen then
              local count = #(state.game.buildQueue or {})
              state.ui._queueFocusIndex = math.max(1, (state.ui._queueFocusIndex or 1) - 1)
            end
          end
        end
      end
      
      -- Update last stick state
      state.ui._lastStickState.x = ax
      state.ui._lastStickState.y = ay
    end
    
    -- Virtual cursor movement (only when not suppressed)
    local suppressCursor = state.ui._handheldMode and (
      state.ui.isBuildMenuOpen or state.ui.isMissionSelectorOpen or state.ui.isVillagersPanelOpen or state.ui.isBuildQueueOpen or state.ui.isFoodPanelOpen or state.ui.isPaused or state.ui._wheelMenuActive or state.ui._controlsOverlayOpen
    )
    if not suppressCursor then
      -- Much lower speed and use cubic response for precision near center
      local maxSpeed = 180
      local ax3 = ax * math.abs(ax) * math.abs(ax)
      local ay3 = ay * math.abs(ay) * math.abs(ay)
      local scale = state.camera.scale or 1
      local vx = (ax3 * maxSpeed * dt)
      local vy = (ay3 * maxSpeed * dt)
      -- Much larger deadzone for precision
      if math.abs(ax) > 0.35 or math.abs(ay) > 0.35 then
        state.ui._useVirtualCursor = true
        state.ui._virtualCursor.x = utils.clamp((state.ui._virtualCursor.x or 0) + vx, 0, love.graphics.getWidth())
        state.ui._virtualCursor.y = utils.clamp((state.ui._virtualCursor.y or 0) + vy, 0, love.graphics.getHeight())
      end
    end
  end
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

  -- Mouse/touch edge panning (not speed-scaled) and virtual-cursor edge pan on handheld
  local mx, my = love.mouse.getPosition()
  if state.ui._handheldMode and state.ui._useVirtualCursor and state.ui._virtualCursor and not state.ui._wheelMenuActive then
    mx, my = state.ui._virtualCursor.x or mx, state.ui._virtualCursor.y or my
  end
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
  if state.ui._startupChoiceOpen then
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0,0,0,0.5)
    love.graphics.rectangle('fill', 0, 0, w, h)
    local mw, mh = 520, 240
    local mx, my = (w - mw) / 2, (h - mh) / 2
    love.graphics.setColor(0.95, 0.90, 0.80, 1.0)
    love.graphics.rectangle('fill', mx, my, mw, mh, 10, 10)
    love.graphics.setColor(0.25, 0.18, 0.10, 1.0)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle('line', mx, my, mw, mh, 10, 10)
    love.graphics.setLineWidth(1)
    local title = "Choose Display Mode"
    local tw = love.graphics.getFont():getWidth(title)
    love.graphics.print(title, mx + (mw - tw) / 2, my + 18)
    local bx, by, bw, bh = mx + 40, my + 80, 200, 60
    local bx2 = mx + mw - 40 - 200
    local focus = state.ui._startupChoiceFocus or 1
    -- Desktop button
    love.graphics.setColor(0.85, 0.8, 0.7, 1)
    love.graphics.rectangle('fill', bx, by, bw, bh, 8, 8)
    if focus == 1 then
      love.graphics.setColor(0.2, 0.7, 0.3, 0.3)
      love.graphics.rectangle('fill', bx+4, by+4, bw-8, bh-8, 8, 8)
    end
    love.graphics.setColor(0.2, 0.15, 0.1, 1)
    love.graphics.rectangle('line', bx, by, bw, bh, 8, 8)
    local l1 = "Desktop (current size)"
    love.graphics.print(l1, bx + (bw - love.graphics.getFont():getWidth(l1)) / 2, by + 20)
    -- Retroid button
    love.graphics.setColor(0.85, 0.8, 0.7, 1)
    love.graphics.rectangle('fill', bx2, by, bw, bh, 8, 8)
    if focus == 2 then
      love.graphics.setColor(0.2, 0.7, 0.3, 0.3)
      love.graphics.rectangle('fill', bx2+4, by+4, bw-8, bh-8, 8, 8)
    end
    love.graphics.setColor(0.2, 0.15, 0.1, 1)
    love.graphics.rectangle('line', bx2, by, bw, bh, 8, 8)
    local l2 = "Retroid Pocket 4 Pro (1334x750)"
    love.graphics.print(l2, bx2 + (bw - love.graphics.getFont():getWidth(l2)) / 2, by + 20)
    return
  end
  -- World space draw
  love.graphics.push()
  love.graphics.scale(state.camera.scale, state.camera.scale)
  love.graphics.translate(-state.camera.x, -state.camera.y)

  -- Grass-like background tiling for depth
  do
    local TILE = C.TILE_SIZE
    local screenW, screenH = love.graphics.getDimensions()
    local visibleW = screenW / (state.camera.scale or 1)
    local visibleH = screenH / (state.camera.scale or 1)
    local startX = math.floor(state.camera.x / TILE) - 1
    local startY = math.floor(state.camera.y / TILE) - 1
    local endX = math.ceil((state.camera.x + visibleW) / TILE) + 1
    local endY = math.ceil((state.camera.y + visibleH) / TILE) + 1
    for ty = startY, endY do
      for tx = startX, endX do
        local px = tx * TILE
        local py = ty * TILE
        -- base patch (lighter)
        love.graphics.setColor(0.22, 0.40, 0.22, 1.0)
        love.graphics.rectangle('fill', px, py, TILE, TILE)
        -- blades overlay with slight noise (hash)
        local n = math.abs(((tx * 73856093 + ty * 19349663) % 5))
        local a = 0.07 + (n * 0.02)
        love.graphics.setColor(0.30, 0.50, 0.26, a)
        love.graphics.rectangle('fill', px + 2, py + 2, TILE - 4, TILE - 4, 6, 6)
        love.graphics.setColor(0.26, 0.46, 0.22, a * 0.9)
        love.graphics.rectangle('line', px + 3, py + 3, TILE - 6, TILE - 6, 6, 6)
      end
    end
  end

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

  -- Draw virtual cursor when a gamepad is present (UI-space)
  if gamepad and gamepad:isConnected() and state.ui._virtualCursor then
    local x, y = state.ui._virtualCursor.x, state.ui._virtualCursor.y
    if state.ui._useVirtualCursor and not state.ui._wheelMenuActive then
      if state.ui._handheldMode then
        -- Draw highlighted cell instead of cursor
        local tileX, tileY = screenToTile(x, y)
        local worldX = tileX * TILE_SIZE
        local worldY = tileY * TILE_SIZE
        local screenX = (worldX - state.camera.x) * state.camera.scale
        local screenY = (worldY - state.camera.y) * state.camera.scale
        
        -- Pulsing highlight effect
        local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(1, 1, 0.8, 0.8 * pulse)
        love.graphics.rectangle('fill', screenX, screenY, TILE_SIZE * state.camera.scale, TILE_SIZE * state.camera.scale)
        love.graphics.setColor(1, 1, 0.4, 0.9 * pulse)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle('line', screenX, screenY, TILE_SIZE * state.camera.scale, TILE_SIZE * state.camera.scale)
        love.graphics.setLineWidth(1)
      else
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle('fill', x, y, 4)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.circle('line', x, y, 4)
      end
    end
  end

  -- UI draw
  ui.drawTopButtons(state)
  ui.drawBuildMenu(state, state.buildingDefs)
  ui.drawWheelMenu(state)
  -- Controls overlay on top of menus
  ui.drawControlsOverlay(state)
  ui.drawHUD(state)
  ui.drawFoodPanel(state)
  ui.drawBuildQueue(state)
  ui.drawVillagersPanel(state)
  if state.ui.showMinimap then ui.drawMiniMap(state) end
  if state.ui.showMissionPanel then ui.drawMissionPanel(state) end
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
      love.graphics.setColor(0.35, 0.22, 0.12, 0.9)
      love.graphics.rectangle('fill', tip.sx - 2, tip.sy + 2, tw + 4, th + 4, 6, 6)
      love.graphics.setColor(0.95, 0.82, 0.60, 1.0)
      love.graphics.rectangle('fill', tip.sx, tip.sy, tw, th, 6, 6)
      love.graphics.setColor(0.78, 0.54, 0.34, 1.0)
      love.graphics.rectangle('line', tip.sx, tip.sy, tw, th, 6, 6)
      love.graphics.setColor(0.18, 0.11, 0.06, 1.0)
      love.graphics.print(tip.text, tip.sx + 6, tip.sy + 4)
    end
  end

  -- bottom hint removed in handheld/desktop per request

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
  if state.ui._startupChoiceOpen then
    if button ~= 1 then return end
    local w, h = love.graphics.getDimensions()
    local mw, mh = 520, 240
    local mx, my = (w - mw) / 2, (h - mh) / 2
    local bx, by, bw, bh = mx + 40, my + 80, 200, 60
    local bx2 = mx + mw - 40 - 200
    if utils.isPointInRect(x, y, bx, by, bw, bh) then
      startGameWithPreset('desktop')
      return
    elseif utils.isPointInRect(x, y, bx2, by, bw, bh) then
      startGameWithPreset('retroid')
      return
    end
    return
  end
  -- Keep virtual cursor disabled while the build menu is open
  if state.ui.isBuildMenuOpen then
    state.ui._useVirtualCursor = false
  else
    state.ui._useVirtualCursor = state.ui._handheldMode and state.ui._useVirtualCursor or false
  end
  -- If using virtual cursor, redirect to its position to ensure hover/click parity
  if state.ui._handheldMode and state.ui._useVirtualCursor and state.ui._virtualCursor then
    x, y = state.ui._virtualCursor.x or x, state.ui._virtualCursor.y or y
  end
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
        if option.key == 'road' then
          state.ui.isPlacingRoad = true
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isBuildMenuOpen = false
          state.ui.roadStartTile = nil
          state.ui._isFreeInitialBuilder = nil
          return
        else
          state.ui.selectedBuildingType = option.key
          state.ui.isPlacingBuilding = true
          state.ui.isBuildMenuOpen = false
          state.ui.buildMenuAlpha = 0
          state.ui._isFreeInitialBuilder = nil
          return
        end
      else
        state.ui.isBuildMenuOpen = false
        state.ui.buildMenuAlpha = 0
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

  -- Mission selector button click
  if state.ui._missionSelectorButtons and state.ui._missionSelectorButtons.open then
    local b = state.ui._missionSelectorButtons.open
    if x >= b.x and x <= b.x + b.width and y >= b.y and y <= b.y + b.height then
      state.ui.isMissionSelectorOpen = not state.ui.isMissionSelectorOpen
      state.ui.isPaused = state.ui.isMissionSelectorOpen or state.ui.isPaused
      return
    end
  end

  -- Mission selector panel options
  if state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
    for _, btn in ipairs(state.ui._missionSelectorButtons) do
      if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
        local missions = require('src.missions')
        local id = btn.id
        if id == 1 then
          require('src.missions').reset(state)
        elseif id == 2 then
          require('src.missions').reset(state); state.mission.stage = 1; -- init
          -- complete stage 1 instantly and advance to 2
          state.mission.completed = true; state.mission.advanceTimer = 0; missions.update(state, 0.01)
        else
          -- brute: set stage and assign objectives like the auto-advance path does
          if id == 3 then
            state.mission.stage = 2; state.mission.completed = true; state.mission.advanceTimer = 0; missions.update(state, 0.01)
          elseif id == 4 then
            state.mission.stage = 3; state.mission.completed = true; state.mission.advanceTimer = 0; missions.update(state, 0.01)
          elseif id == 5 then
            state.mission.stage = 4; state.mission.completed = true; state.mission.advanceTimer = 0; missions.update(state, 0.01)
          elseif id == 6 then
            state.mission.stage = 5; state.mission.completed = true; state.mission.advanceTimer = 0; missions.update(state, 0.01)
          elseif id == 7 then
            state.mission.stage = 6; state.mission.completed = true; state.mission.advanceTimer = 0; missions.update(state, 0.01)
          end
        end
        state.ui.isMissionSelectorOpen = false
        state.ui.isPaused = false
        return
      end
    end
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
  if state.ui._startupChoiceOpen then
    if key == 'left' or key == 'a' then
      state.ui._startupChoiceFocus = 1
      return
    elseif key == 'right' or key == 'd' then
      state.ui._startupChoiceFocus = 2
      return
    elseif key == 'return' or key == 'kpenter' or key == 'space' then
      startGameWithPreset(state.ui._startupChoiceFocus == 2 and 'retroid' or 'desktop')
      return
    elseif key == 'escape' then
      startGameWithPreset('desktop')
      return
    end
  end
  if state.ui._isFreeInitialBuilder then
    return
  end
  -- Handheld keyboard mimic of controller buttons and left stick
  if state.ui._handheldMode then
    if key == 'a' then
      -- Handheld: A selects/acts. In queue, toggle reorder mode.
      if state.ui._handheldMode and state.ui.isBuildQueueOpen then
        state.ui._queueReorderActive = not (state.ui._queueReorderActive or false)
        if (not state.ui._queueFocusIndex) then state.ui._queueFocusIndex = 1 end
        return
      end
      if state.ui.isBuildMenuOpen and state.ui._buildMenuFocus then
        local ui_mod = require('src.ui')
        local opt = ui_mod.buildMenu.options[state.ui._buildMenuFocus]
        if opt then
          state.ui.selectedBuildingType = opt.key
          state.ui.isPlacingBuilding = true
          state.ui.isBuildMenuOpen = false
          state.ui.buildMenuAlpha = 0
          return
        end
      elseif state.ui.isPaused and state.ui._pauseMenuFocus then
        local ui_mod = require('src.ui')
        local opt = ui_mod.pauseMenu.options[state.ui._pauseMenuFocus]
        if opt then
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
          return
        end
      elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
        local idx = state.ui._missionSelectorFocus or 1
        local btn = state.ui._missionSelectorButtons[idx]
        if btn then
          love.mousepressed(btn.x + 2, btn.y + 2, 1)
          return
        end
      elseif state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
        local idx = state.ui._villagersPanelFocus or 1
        local entry = state.ui._villagersPanelButtons[idx]
        if entry and entry.add then
          -- simulate pressing the '+' button for the focused row
          love.mousepressed(entry.add.x + 2, entry.add.y + 2, 1)
          return
        end
      elseif state.ui.isBuildQueueOpen and state.ui._handheldMode then
        -- Toggle reorder mode for handheld queue
        state.ui._queueReorderActive = not (state.ui._queueReorderActive or false)
        if (not state.ui._queueFocusIndex) then state.ui._queueFocusIndex = 1 end
        return
      end
      local x = (state.ui._virtualCursor and state.ui._virtualCursor.x) or love.mouse.getX()
      local y = (state.ui._virtualCursor and state.ui._virtualCursor.y) or love.mouse.getY()
      love.mousepressed(x, y, 1)
      return
    elseif key == 'b' then
      -- Handheld: B returns/closes current panels
      if state.ui._handheldMode then
        if state.ui.isBuildQueueOpen then
          state.ui.isBuildQueueOpen = false
          state.ui._queueReorderActive = false
          return
        elseif state.ui.isVillagersPanelOpen then
          state.ui.isVillagersPanelOpen = false
          return
        elseif state.ui.isBuildMenuOpen then
          state.ui.isBuildMenuOpen = false
          return
        end
      end
      local x, y = state.ui._virtualCursor.x or 0, state.ui._virtualCursor.y or 0
      love.mousepressed(x, y, 2)
    elseif key == 'x' then
      if state.ui._handheldMode then
        -- Toggle handheld controls overlay
        state.ui._controlsOverlayOpen = not state.ui._controlsOverlayOpen
        if state.ui._controlsOverlayOpen then
          -- Close other panels for clarity
          state.ui.isBuildMenuOpen = false
          state.ui.isVillagersPanelOpen = false
          state.ui.isBuildQueueOpen = false
          state.ui.isPaused = false
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isPlacingRoad = false
          state.ui.roadStartTile = nil
          -- Disable virtual cursor while overlay is shown
          state.ui._useVirtualCursor = false
        end
      else
        state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
        if state.ui.isBuildMenuOpen then
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isPlacingRoad = false
          state.ui.roadStartTile = nil
          state.ui.isVillagersPanelOpen = false
          state.ui._buildMenuFocus = 1
          -- disable virtual cursor while navigating menu by stick/buttons
          state.ui._useVirtualCursor = false
        end
      end
    elseif key == 'y' then
      -- Y key disabled in handheld mode
      if not state.ui._handheldMode then
        state.ui.showMissionPanel = not state.ui.showMissionPanel
      end
      return
    elseif key == 'r' and state.ui._handheldMode then
      -- Keyboard fallback for R2 trigger (hold R key)
      state.ui._wheelMenuActive = true
      state.ui._wheelMenuSelection = 0
      return
    elseif key == 'l' and state.ui._handheldMode then
      -- Keyboard fallback for L2 trigger (press L key)
      local speeds = {1, 2, 4, 8}
      local currentSpeed = state.time.speed or 1
      local currentIndex = 1
      for i, speed in ipairs(speeds) do
        if speed == currentSpeed then
          currentIndex = i
          break
        end
      end
      local nextIndex = (currentIndex % #speeds) + 1
      state.time.speed = speeds[nextIndex]
      return
    elseif key == 'up' then
      if state.ui._handheldMode then
        -- D-pad up opens build queue in handheld mode
        state.ui.isBuildQueueOpen = not state.ui.isBuildQueueOpen
        if state.ui.isBuildQueueOpen then
          -- Close other panels for clarity
          state.ui.isBuildMenuOpen = false
          state.ui.isVillagersPanelOpen = false
          state.ui.isPaused = false
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isPlacingRoad = false
          state.ui.roadStartTile = nil
          state.ui._queueFocusIndex = 1
          state.ui._queueReorderActive = false
        end
      else
        -- Desktop mode: normal navigation
        if state.ui.isBuildMenuOpen then
          moveBuildMenuFocus(0, -1)
        elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
          state.ui._missionSelectorFocus = math.max(1, (state.ui._missionSelectorFocus or 1) - 1)
        elseif state.ui.isPaused and ui.pauseMenu and ui.pauseMenu.options then
          state.ui._pauseMenuFocus = math.max(1, (state.ui._pauseMenuFocus or 1) - 1)
        else
          state.ui._useVirtualCursor = true
          state.ui._virtualCursor.y = math.max(0, (state.ui._virtualCursor.y or 0) - 24)
        end
      end
      return
    elseif key == 'down' then
      if state.ui._handheldMode then
        -- D-pad down opens villagers panel in handheld mode
        state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
        if state.ui.isVillagersPanelOpen then
          -- Close other panels for clarity
          state.ui.isBuildMenuOpen = false
          state.ui.isBuildQueueOpen = false
          state.ui.isPaused = false
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isPlacingRoad = false
          state.ui.roadStartTile = nil
          state.ui._villagersPanelFocus = 1
        end
      else
        -- Desktop mode: normal navigation
        if state.ui.isBuildMenuOpen then
          moveBuildMenuFocus(0, 1)
        elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
          state.ui._missionSelectorFocus = math.min(#(state.ui._missionSelectorButtons or {}), (state.ui._missionSelectorFocus or 1) + 1)
        elseif state.ui.isPaused and ui.pauseMenu and ui.pauseMenu.options then
          state.ui._pauseMenuFocus = math.min(#ui.pauseMenu.options, (state.ui._pauseMenuFocus or 1) + 1)
        else
          state.ui._useVirtualCursor = true
          state.ui._virtualCursor.y = math.min(love.graphics.getHeight(), (state.ui._virtualCursor.y or 0) + 24)
        end
      end
      return
    elseif key == 'up' then
      if state.ui.isBuildMenuOpen then
        state.ui._buildMenuFocus = math.max(1, (state.ui._buildMenuFocus or 1) - 1)
      else
        state.ui._useVirtualCursor = true
        state.ui._virtualCursor.y = math.max(0, (state.ui._virtualCursor.y or 0) - 24)
      end
      return
    
    elseif key == 'left' then
      if state.ui.isBuildMenuOpen then
        moveBuildMenuFocus(-1, 0)
      else
        state.ui._useVirtualCursor = true
        state.ui._virtualCursor.x = math.max(0, (state.ui._virtualCursor.x or 0) - 24)
      end
      return
    elseif key == 'right' then
      if state.ui.isBuildMenuOpen then
        moveBuildMenuFocus(1, 0)
      else
        state.ui._useVirtualCursor = true
        state.ui._virtualCursor.x = math.min(love.graphics.getWidth(), (state.ui._virtualCursor.x or 0) + 24)
      end
      return
    end
  end
  -- Handheld: d-pad/page keys for UI toggles
  if key == 'tab' then
    state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
    return
  end
  if key == 'escape' then
    -- Close any open overlays/panels/modes without opening the pause menu
    local closed = false
    if state.ui.isBuildMenuOpen then state.ui.isBuildMenuOpen = false; closed = true end
    if state.ui.isFoodPanelOpen then state.ui.isFoodPanelOpen = false; closed = true end
    if state.ui.isMissionSelectorOpen then state.ui.isMissionSelectorOpen = false; closed = true end
    if state.ui.isBuildQueueOpen then state.ui.isBuildQueueOpen = false; closed = true end
    if state.ui.isVillagersPanelOpen then state.ui.isVillagersPanelOpen = false; closed = true end
    if state.ui._saveLoadMode then state.ui._saveLoadMode = nil; closed = true end
    if state.ui.isPlacingBuilding then state.ui.isPlacingBuilding = false; state.ui.selectedBuildingType = nil; closed = true end
    if state.ui.isPlacingRoad then state.ui.isPlacingRoad = false; state.ui.roadStartTile = nil; closed = true end
    if state.ui.isDemolishMode then state.ui.isDemolishMode = false; closed = true end
    if closed then
      state.ui.isPaused = false
      return
    end
    -- Nothing to close: toggle pause menu
    state.ui.isPaused = not state.ui.isPaused
    if state.ui.isPaused then
      state.ui._pauseMenuFocus = 1
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
    -- In handheld, Roads live in Build Menu; keep keyboard R for desktop only
    if not state.ui._handheldMode then
      state.ui.isPlacingRoad = not state.ui.isPlacingRoad
      state.ui.isPlacingBuilding = false
      state.ui.selectedBuildingType = nil
      -- Show instructions as a prompt when road mode is activated
      if state.ui.isPlacingRoad then
        state.ui.prompts = state.ui.prompts or {}
        local tag = 'road_hint'
        local text = "Roads: Click to set start, click again to extend. Drag along tiles. Starts/ends snap next to buildings. Press R to exit."
        local found = false
        for _, p in ipairs(state.ui.prompts) do if p.tag == tag then p.text = text; p.t = 0; p.duration = 6; p.useRealTime = true; found = true; break end end
        if not found then table.insert(state.ui.prompts, { tag = tag, text = text, t = 0, duration = 6, useRealTime = true }) end
      else
        -- Remove the hint when exiting road mode
        if state.ui.prompts then
          local newList = {}
          for _, p in ipairs(state.ui.prompts) do if p.tag ~= 'road_hint' then table.insert(newList, p) end end
          state.ui.prompts = newList
        end
      end
    end
  elseif key == 'v' then
    state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
  elseif key == 'm' then
    state.ui.isMissionSelectorOpen = not state.ui.isMissionSelectorOpen
    -- Do not toggle global pause menu; the selector acts as its own overlay
    return
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
  elseif key == 'pageup' and state.ui._handheldMode then
    -- Map shoulder equivalent for speed up on handheld keyboards
    local map = { [1]=1,[2]=2,[4]=4,[8]=8 }
    local s = state.time.speed or 1
    if s == 1 then state.time.speed = 2 elseif s == 2 then state.time.speed = 4 elseif s == 4 then state.time.speed = 8 end
  elseif key == 'pagedown' and state.ui._handheldMode then
    local s = state.time.speed or 1
    if s == 8 then state.time.speed = 4 elseif s == 4 then state.time.speed = 2 elseif s == 2 then state.time.speed = 1 end
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
    local map = { h = 'house', l = 'lumberyard', w = 'warehouse', b = 'builder', f = 'farm', r = 'research' }
    local sel = map[key]
    if sel then
      state.ui.selectedBuildingType = sel
      state.ui.isPlacingBuilding = true
      state.ui.isBuildMenuOpen = false
    end
  end
end

-- Mouse controls the virtual cursor in handheld mode
function love.mousemoved(x, y, dx, dy, istouch)
  if state.ui._handheldMode then
    if state.ui.isBuildMenuOpen or state.ui.isMissionSelectorOpen or state.ui.isVillagersPanelOpen or state.ui.isBuildQueueOpen or state.ui.isFoodPanelOpen or state.ui.isPaused or state.ui._wheelMenuActive or state.ui._controlsOverlayOpen then return end
    state.ui._useVirtualCursor = true
    state.ui._virtualCursor = state.ui._virtualCursor or { x = 0, y = 0 }
    state.ui._virtualCursor.x = utils.clamp(x, 0, love.graphics.getWidth())
    state.ui._virtualCursor.y = utils.clamp(y, 0, love.graphics.getHeight())
  end
end

function love.gamepadpressed(joy, button)
  gamepad = joy
  if state.ui._startupChoiceOpen then
    if button == 'dpleft' then state.ui._startupChoiceFocus = 1 return end
    if button == 'dpright' then state.ui._startupChoiceFocus = 2 return end
    if button == 'a' then
      startGameWithPreset(state.ui._startupChoiceFocus == 2 and 'retroid' or 'desktop')
      return
    end
  end
  -- While Villagers panel is open, use L/R shoulders to change workers and block other actions
  if state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
    local idx = state.ui._villagersPanelFocus or 1
    local entry = state.ui._villagersPanelButtons[idx]
    if entry and entry.b then
      if button == 'rightshoulder' then
        require('src.buildings').assignOne(state, entry.b)
        return
      elseif button == 'leftshoulder' then
        require('src.buildings').unassignOne(state, entry.b)
        return
      end
    end
  end
  if button == 'a' then
    if state.ui.isBuildQueueOpen and state.ui._handheldMode then
      -- A button in queue panel: toggle selection of current item for reordering
      local queueCount = #(state.game.buildQueue or {})
      if queueCount > 0 then
        state.ui._queueFocusIndex = state.ui._queueFocusIndex or 1
        state.ui._queueSelectedIndex = state.ui._queueSelectedIndex or nil
        
        if state.ui._queueSelectedIndex == state.ui._queueFocusIndex then
          -- Deselect if same item
          state.ui._queueSelectedIndex = nil
        else
          -- Select current focused item
          state.ui._queueSelectedIndex = state.ui._queueFocusIndex
        end
      end
      return
    elseif state.ui.isBuildMenuOpen and state.ui._buildMenuFocus then
      local ui_mod = require('src.ui')
      local opt = ui_mod.buildMenu.options[state.ui._buildMenuFocus]
      if opt then
        state.ui.selectedBuildingType = opt.key
        state.ui.isPlacingBuilding = true
        state.ui.isBuildMenuOpen = false
        state.ui.buildMenuAlpha = 0
        return
      end
    elseif state.ui.isPaused and state.ui._pauseMenuFocus then
      local ui_mod = require('src.ui')
      local opt = ui_mod.pauseMenu.options[state.ui._pauseMenuFocus]
      if opt then
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
        return
      end
    end
    local x, y = state.ui._virtualCursor.x or 0, state.ui._virtualCursor.y or 0
    love.mousepressed(x, y, 1)
  elseif button == 'b' then
    if state.ui.isBuildQueueOpen and state.ui._handheldMode then
      -- B button in queue panel: close the panel and clear selections
      state.ui.isBuildQueueOpen = false
      state.ui._queueFocusIndex = nil
      state.ui._queueSelectedIndex = nil
      return
    elseif state.ui.isVillagersPanelOpen and state.ui._handheldMode then
      -- B button in villagers panel: close the panel
      state.ui.isVillagersPanelOpen = false
      state.ui._villagersPanelFocus = nil
      return
    end
    local x, y = state.ui._virtualCursor.x or 0, state.ui._virtualCursor.y or 0
    love.mousepressed(x, y, 2)
  elseif button == 'x' then
    if state.ui._handheldMode then
      -- Toggle handheld controls overlay
      state.ui._controlsOverlayOpen = not state.ui._controlsOverlayOpen
      if state.ui._controlsOverlayOpen then
        -- Close other panels for clarity
        state.ui.isBuildMenuOpen = false
        state.ui.isVillagersPanelOpen = false
        state.ui.isBuildQueueOpen = false
        state.ui.isPaused = false
        state.ui.isPlacingBuilding = false
        state.ui.selectedBuildingType = nil
        state.ui.isPlacingRoad = false
        state.ui.roadStartTile = nil
        -- Disable virtual cursor while overlay is shown
        state.ui._useVirtualCursor = false
      end
    else
      state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
      if state.ui.isBuildMenuOpen then
        state.ui.isPlacingBuilding = false
        state.ui.selectedBuildingType = nil
        state.ui.isPlacingRoad = false
        state.ui.roadStartTile = nil
        state.ui.isVillagersPanelOpen = false
        state.ui._buildMenuFocus = 1
        -- disable virtual cursor while navigating menu by stick/buttons
        state.ui._useVirtualCursor = false
      end
    end
  elseif button == 'dpup' then
    if state.ui._handheldMode then
      -- D-pad up opens build queue in handheld mode
      state.ui.isBuildQueueOpen = not state.ui.isBuildQueueOpen
      if state.ui.isBuildQueueOpen then
        -- Initialize queue navigation
        local queueCount = #(state.game.buildQueue or {})
        if queueCount > 0 then
          state.ui._queueFocusIndex = 1
        else
          state.ui._queueFocusIndex = nil
        end
        state.ui._queueSelectedIndex = nil
        -- Close other panels for clarity
        state.ui.isBuildMenuOpen = false
        state.ui.isVillagersPanelOpen = false
        state.ui.isPaused = false
        state.ui.isPlacingBuilding = false
        state.ui.selectedBuildingType = nil
        state.ui.isPlacingRoad = false
        state.ui.roadStartTile = nil
      end
    else
      -- Desktop mode: normal menu navigation
      if state.ui.isBuildMenuOpen then
        moveBuildMenuFocus(0, -1)
      elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
        state.ui._missionSelectorFocus = math.max(1, (state.ui._missionSelectorFocus or 1) - 1)
      elseif state.ui.isPaused then
        movePauseMenuFocus(-1)
      end
    end
  elseif button == 'dpdown' then
    if state.ui._handheldMode then
      -- D-pad down opens villagers panel in handheld mode
      state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
      if state.ui.isVillagersPanelOpen then
        -- Close other panels for clarity
        state.ui.isBuildMenuOpen = false
        state.ui.isBuildQueueOpen = false
        state.ui.isPaused = false
        state.ui.isPlacingBuilding = false
        state.ui.selectedBuildingType = nil
        state.ui.isPlacingRoad = false
        state.ui.roadStartTile = nil
      end
    else
      -- Desktop mode: normal menu navigation
      if state.ui.isBuildMenuOpen then
        moveBuildMenuFocus(0, 1)
      elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
        state.ui._missionSelectorFocus = math.min(#(state.ui._missionSelectorButtons or {}), (state.ui._missionSelectorFocus or 1) + 1)
      elseif state.ui.isPaused then
        movePauseMenuFocus(1)
      end
    end
  elseif button == 'dpleft' then
    if state.ui._handheldMode then
      -- Toggle missions panel in handheld mode
      state.ui.showMissionPanel = not state.ui.showMissionPanel
    else
      if state.ui.isBuildMenuOpen then
        moveBuildMenuFocus(-1, 0)
      end
    end
  elseif button == 'dpright' then
    if state.ui._handheldMode then
      -- D-pad right opens build menu in handheld mode
      state.ui.isBuildMenuOpen = not state.ui.isBuildMenuOpen
      if state.ui.isBuildMenuOpen then
        -- Close other panels for clarity
        state.ui.isVillagersPanelOpen = false
        state.ui.isBuildQueueOpen = false
        state.ui.isPaused = false
        state.ui.isPlacingBuilding = false
        state.ui.selectedBuildingType = nil
        state.ui.isPlacingRoad = false
        state.ui.roadStartTile = nil
      end
    else
      -- Desktop mode: normal menu navigation
      if state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
        state.ui._missionSelectorFocus = math.min(#(state.ui._missionSelectorButtons or {}), (state.ui._missionSelectorFocus or 1) + 1)
      elseif state.ui.isPaused then
        movePauseMenuFocus(1)
      end
    end
  elseif button == 'y' then
    -- Y button disabled in handheld mode
    if not state.ui._handheldMode then
      -- Toggle missions panel (desktop only)
      state.ui.showMissionPanel = not state.ui.showMissionPanel
    end
  elseif button == 'start' then
    if state.ui.isFoodPanelOpen then
      state.ui.isFoodPanelOpen = false
      state.ui.isPaused = false
    else
      state.ui.isPaused = not state.ui.isPaused
      if state.ui.isPaused then
        state.ui._pauseMenuFocus = 1
      end
    end
  elseif button == 'back' or button == 'guide' then
    state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
    state.ui.isBuildMenuOpen = false
    state.ui.isPlacingBuilding = false
    state.ui.selectedBuildingType = nil
    state.ui.isPlacingRoad = false
    state.ui.roadStartTile = nil
  elseif button == 'leftshoulder' then
    -- In retroid mode, L2 can also be mapped to left shoulder button
    if state.ui._handheldMode then
      local speeds = {1, 2, 4, 8}
      local currentSpeed = state.time.speed or 1
      local currentIndex = 1
      for i, speed in ipairs(speeds) do
        if speed == currentSpeed then
          currentIndex = i
          break
        end
      end
      local nextIndex = (currentIndex % #speeds) + 1
      state.time.speed = speeds[nextIndex]
    else
      local s = state.time.speed or 1
      if s == 8 then state.time.speed = 4 elseif s == 4 then state.time.speed = 2 elseif s == 2 then state.time.speed = 1 end
    end
  elseif button == 'rightshoulder' then
    -- In retroid mode, R2 can also be mapped to right shoulder button
    if state.ui._handheldMode then
      state.ui._wheelMenuActive = true
      state.ui._wheelMenuSelection = 0
    else
      local s = state.time.speed or 1
      if s == 1 then state.time.speed = 2 elseif s == 2 then state.time.speed = 4 elseif s == 4 then state.time.speed = 8 end
    end
  end
end

function love.gamepadaxis(joy, axis, value)
  gamepad = joy
  
  -- Debug: Print all axes to help identify R2
  if state.ui._handheldMode and math.abs(value) > 0.1 then
    print("Axis:", axis, "Value:", value)
  end
  
  -- L2 trigger handling for game speed switching in retroid mode
  if state.ui._handheldMode and (axis == 'lefttrigger' or axis == 'triggerleft') then
    local wasActive = state.ui._l2Active or false
    local isActive = value > 0.3
    
    -- L2 just pressed
    if isActive and not wasActive then
      local speeds = {1, 2, 4, 8}
      local currentSpeed = state.time.speed or 1
      local currentIndex = 1
      for i, speed in ipairs(speeds) do
        if speed == currentSpeed then
          currentIndex = i
          break
        end
      end
      local nextIndex = (currentIndex % #speeds) + 1
      state.time.speed = speeds[nextIndex]
    end
    
    state.ui._l2Active = isActive
  end
  
  -- R2 trigger handling for wheel menu in retroid mode
  if state.ui._handheldMode and (axis == 'righttrigger' or axis == 'triggerright') then
    local wasActive = state.ui._wheelMenuActive
    state.ui._wheelMenuActive = value > 0.3
    
    -- Debug output to see if R2 is being detected
    if state.ui._handheldMode then
      print("R2 axis:", axis, "value:", value, "active:", state.ui._wheelMenuActive)
    end
    
    -- Wheel menu just activated
    if state.ui._wheelMenuActive and not wasActive then
      -- Start with no selection (neutral center)
      state.ui._wheelMenuSelection = 0
      -- Disable virtual cursor when wheel menu is active
      state.ui._useVirtualCursor = false
    end
    
    -- Wheel menu just deactivated (R2 released)
    if not state.ui._wheelMenuActive and wasActive then
      -- Select the current building type (only if something is selected)
      if state.ui._wheelMenuSelection > 0 then
        local ui_mod = require('src.ui')
        local opts = ui_mod.buildMenu.options or {}
        local selectedOpt = opts[state.ui._wheelMenuSelection]
        if selectedOpt then
          if selectedOpt.key == 'road' then
            state.ui.isPlacingRoad = true
            state.ui.isPlacingBuilding = false
            state.ui.selectedBuildingType = nil
            state.ui.roadStartTile = nil
          else
            state.ui.selectedBuildingType = selectedOpt.key
            state.ui.isPlacingBuilding = true
          end
        end
      end
    end
  end
  
  -- D-pad emulation varies; also support axes for menu focus
  if state.ui.isBuildMenuOpen then
    if (axis == 'lefty' or axis == 'dpdown') and value > 0.5 then
      moveBuildMenuFocus(0, 1)
    elseif (axis == 'lefty' or axis == 'dpup') and value < -0.5 then
      moveBuildMenuFocus(0, -1)
    elseif (axis == 'leftx' or axis == 'dpright') and value > 0.5 then
      moveBuildMenuFocus(1, 0)
    elseif (axis == 'leftx' or axis == 'dpleft') and value < -0.5 then
      moveBuildMenuFocus(-1, 0)
    end
  end

  -- Handheld: D-pad up/down open panels with edge detection when reported as axes
  if state.ui._handheldMode then
    if axis == 'dpup' then
      if (state.ui._lastDpadAxis.up or 0) <= 0.5 and value > 0.5 then
        state.ui.isBuildQueueOpen = not state.ui.isBuildQueueOpen
        if state.ui.isBuildQueueOpen then
          state.ui.isBuildMenuOpen = false
          state.ui.isVillagersPanelOpen = false
          state.ui.isPaused = false
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isPlacingRoad = false
          state.ui.roadStartTile = nil
          state.ui._queueFocusIndex = 1
          state.ui._queueReorderActive = false
        end
      end
      state.ui._lastDpadAxis.up = value
    elseif axis == 'dpdown' then
      if (state.ui._lastDpadAxis.down or 0) <= 0.5 and value > 0.5 then
        state.ui.isVillagersPanelOpen = not state.ui.isVillagersPanelOpen
        if state.ui.isVillagersPanelOpen then
          state.ui.isBuildMenuOpen = false
          state.ui.isBuildQueueOpen = false
          state.ui.isPaused = false
          state.ui.isPlacingBuilding = false
          state.ui.selectedBuildingType = nil
          state.ui.isPlacingRoad = false
          state.ui.roadStartTile = nil
          state.ui._villagersPanelFocus = 1
        end
      end
      state.ui._lastDpadAxis.down = value
    elseif axis == 'dpleft' then
      if (state.ui._lastDpadAxis.left or 0) <= 0.5 and value > 0.5 then
        state.ui.showMissionPanel = not state.ui.showMissionPanel
      end
      state.ui._lastDpadAxis.left = value
    end

    -- Left stick edge-detect for menu navigation (axis events)
    if axis == 'lefty' then
      local threshold = 0.35
      local lastY = state.ui._lastStickState.y or 0
      if value > threshold and lastY <= threshold then
        if state.ui.isBuildMenuOpen then
          moveBuildMenuFocus(0, 1)
        elseif state.ui.isPaused then
          movePauseMenuFocus(1)
        elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
          local count = #(state.ui._missionSelectorButtons or {})
          local idx = (state.ui._missionSelectorFocus or 1)
          if idx < count then state.ui._missionSelectorFocus = idx + 1 end
        elseif state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
          local count = #(state.ui._villagersPanelButtons or {})
          state.ui._villagersPanelFocus = math.min(count, (state.ui._villagersPanelFocus or 1) + 1)
        elseif state.ui.isBuildQueueOpen then
          local count = #(state.game.buildQueue or {})
          if count > 0 then
            if state.ui._queueSelectedIndex then
              -- Reorder mode: move selected item down
              local selIdx = state.ui._queueSelectedIndex
              if selIdx < count and state.game.buildQueue then
                local q = state.game.buildQueue
                local tmp = q[selIdx+1]
                q[selIdx+1] = q[selIdx]
                q[selIdx] = tmp
                state.ui._queueSelectedIndex = selIdx + 1
                state.ui._queueFocusIndex = selIdx + 1
              end
            else
              -- Navigation mode: move focus down
              state.ui._queueFocusIndex = math.min(count, (state.ui._queueFocusIndex or 1) + 1)
            end
          end
        end
      elseif value < -threshold and lastY >= -threshold then
        if state.ui.isBuildMenuOpen then
          moveBuildMenuFocus(0, -1)
        elseif state.ui.isPaused then
          movePauseMenuFocus(-1)
        elseif state.ui.isMissionSelectorOpen and state.ui._missionSelectorButtons then
          local idx = (state.ui._missionSelectorFocus or 1)
          if idx > 1 then state.ui._missionSelectorFocus = idx - 1 end
        elseif state.ui.isVillagersPanelOpen and state.ui._villagersPanelButtons then
          state.ui._villagersPanelFocus = math.max(1, (state.ui._villagersPanelFocus or 1) - 1)
        elseif state.ui.isBuildQueueOpen then
          local count = #(state.game.buildQueue or {})
          if count > 0 then
            if state.ui._queueSelectedIndex then
              -- Reorder mode: move selected item up
              local selIdx = state.ui._queueSelectedIndex
              if selIdx > 1 and state.game.buildQueue then
                local q = state.game.buildQueue
                local tmp = q[selIdx-1]
                q[selIdx-1] = q[selIdx]
                q[selIdx] = tmp
                state.ui._queueSelectedIndex = selIdx - 1
                state.ui._queueFocusIndex = selIdx - 1
              end
            else
              -- Navigation mode: move focus up
              state.ui._queueFocusIndex = math.max(1, (state.ui._queueFocusIndex or 1) - 1)
            end
          end
        end
      end
      state.ui._lastStickState.y = value
    elseif axis == 'leftx' then
      local threshold = 0.35
      local lastX = state.ui._lastStickState.x or 0
      if value > threshold and lastX <= threshold then
        if state.ui.isBuildMenuOpen then moveBuildMenuFocus(1, 0) end
      elseif value < -threshold and lastX >= -threshold then
        if state.ui.isBuildMenuOpen then moveBuildMenuFocus(-1, 0) end
      end
      state.ui._lastStickState.x = value
    end
  end
  -- Move virtual cursor with left stick when enabled
  if state.ui._useVirtualCursor and state.ui._virtualCursor then
    local ax = gamepad and (gamepad:getGamepadAxis("leftx") or 0) or 0
    local ay = gamepad and (gamepad:getGamepadAxis("lefty") or 0) or 0
    local speed = 400
    state.ui._virtualCursor.x = utils.clamp((state.ui._virtualCursor.x or 0) + ax * speed * (1/60), 0, love.graphics.getWidth())
    state.ui._virtualCursor.y = utils.clamp((state.ui._virtualCursor.y or 0) + ay * speed * (1/60), 0, love.graphics.getHeight())
  end
  -- Right stick sets zoom velocity; applied smoothly in update
  if state.ui._handheldMode and (axis == 'righty' or axis == 'rightx') then
    local dz = (gamepad and (gamepad:getGamepadAxis('righty') or 0) or 0)
    if math.abs(dz) > 0.1 then
      state.ui._zoomVel = -dz * 1.1 -- slightly slower zoom for precision
    else
      state.ui._zoomVel = 0
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

function love.gamepadreleased(joy, button)
  gamepad = joy
  if button == 'rightshoulder' and state.ui._handheldMode then
    -- Handle wheel menu selection when R2 is released
    if state.ui._wheelMenuActive then
      if state.ui._wheelMenuSelection > 0 then
        local ui_mod = require('src.ui')
        local opts = ui_mod.buildMenu.options or {}
        local selectedOpt = opts[state.ui._wheelMenuSelection]
        if selectedOpt then
          if selectedOpt.key == 'road' then
            state.ui.isPlacingRoad = true
            state.ui.isPlacingBuilding = false
            state.ui.selectedBuildingType = nil
            state.ui.roadStartTile = nil
          else
            state.ui.selectedBuildingType = selectedOpt.key
            state.ui.isPlacingBuilding = true
          end
        end
      end
      state.ui._wheelMenuActive = false
      -- Re-enable virtual cursor when wheel menu is closed
      if state.ui._handheldMode then
        state.ui._useVirtualCursor = true
      end
    end
  end
end

function love.keyreleased(key)
  if key == 'r' and state.ui._handheldMode then
    -- Handle wheel menu selection when R key is released
    if state.ui._wheelMenuActive then
      if state.ui._wheelMenuSelection > 0 then
        local ui_mod = require('src.ui')
        local opts = ui_mod.buildMenu.options or {}
        local selectedOpt = opts[state.ui._wheelMenuSelection]
        if selectedOpt then
          if selectedOpt.key == 'road' then
            state.ui.isPlacingRoad = true
            state.ui.isPlacingBuilding = false
            state.ui.selectedBuildingType = nil
            state.ui.roadStartTile = nil
          else
            state.ui.selectedBuildingType = selectedOpt.key
            state.ui.isPlacingBuilding = true
          end
        end
      end
      state.ui._wheelMenuActive = false
      -- Re-enable virtual cursor when wheel menu is closed
      if state.ui._handheldMode then
        state.ui._useVirtualCursor = true
      end
    end
  end
end