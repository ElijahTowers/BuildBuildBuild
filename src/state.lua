-- state.lua
-- Central game state: resources, camera, world size, building definitions

local constants = require('src.constants')

local state = {}

-- Camera and world limits
state.camera = { x = 0, y = 0, panSpeed = 700, scale = 1.0, minScale = 0.5, maxScale = 2.5 }
state.world = { tilesX = 0, tilesY = 0 }

-- Time of day
state.time = {
  t = 0,           -- seconds elapsed in current day
  dayLength = 180, -- seconds per full day-night cycle
  normalized = 0,  -- 0..1 across the day
  speed = 1,       -- time speed multiplier: 1, 2, 4, 8
  lastIsDay = nil,  -- last computed isDay flag for transition detection
  preNightSpeed = 1  -- remembers speed before switching to 8x at night
}

-- UI state
state.ui = {
  isBuildMenuOpen = false,
  isPlacingBuilding = false,
  selectedBuildingType = nil,
  isPaused = false,
  buildMenuAlpha = 0, -- 0..1 animated alpha/scale for build menu
  previewT = 0,       -- time accumulator for placement preview pulse
  selectedBuilding = nil, -- reference to clicked building (for radius display)
  isPlacingRoad = false,
  roadStartTile = nil,
  isVillagersPanelOpen = false,
  _villagersPanelButtons = nil, -- temp bounds for assign/unassign in panel
  _speedButtons = nil,
  _miniMap = nil,
  showMinimap = true,
  forceGrid = false,
  showHelp = false,
  selectedIndex = 0,
  -- prompt message (legacy single prompt fields)
  promptText = nil,
  promptT = 0,
  promptDuration = 0,
  promptSticky = false,
  _promptUseRealTime = nil,
  -- stacked prompts
  prompts = {},
  -- world rendering options
  showWorldVillagerDots = false,
  -- demolish mode
  isDemolishMode = false
}

-- Resources, population and world entities
state.game = {
	resources = { wood = 50, _spentAny = false },
	productionRates = { wood = 0 },
	population = { total = 0, assigned = 0, capacity = 0 },
	buildings = {},
	trees = {},
	particles = {},
	roads = {}, -- map of road tiles
	villagers = {}, -- persistent villager entities
	bushes = {},
	roadSpeed = { onRoadMultiplier = 1.5 }, -- tuning for road speed bonus
	jobs = { demolitions = {}, _nextId = 1 }
}

-- Building definitions and balance
state.buildingDefs = {
  house = {
    cost = { wood = 10 },
    residents = 3,
    production = nil,
    buildRequired = 10
  },
  lumberyard = {
    cost = { wood = 20 },
    production = nil,
    radiusTiles = 6,
    chopRate = 1.0,
    woodPerTree = 6,
    numWorkers = 2,
    workerSpeed = 120, -- pixels per second
    buildRequired = 12
  },
  warehouse = {
    cost = { wood = 20 },
    capacity = { wood = 200 },
    buildRequired = 14
  },
  builder = {
    cost = { wood = 25 },
    numWorkers = 5,
    workerSpeed = 120,
    buildRate = 2.0, -- build progress per second per worker
    buildRequired = 12,
    residents = 5
  },
  road = {
    costPerTile = { wood = 1 }
  }
}

function state.resetWorldTilesFromScreen()
  local screenW, screenH = love.graphics.getDimensions()
  local baseTilesX = math.floor(screenW / constants.TILE_SIZE)
  local baseTilesY = math.floor(screenH / constants.TILE_SIZE)
  state.world.tilesX = math.max(32, baseTilesX * 4)
  state.world.tilesY = math.max(32, baseTilesY * 4)
end

function state.restart()
  state.game.buildings = {}
  state.game.trees = {}
  state.game.particles = {}
  state.game.roads = {}
  state.game.villagers = {}
  state.game.bushes = {}
  state.game.resources = { wood = 50 }
  state.game.productionRates = { wood = 0 }
  state.game.population = { total = 0, assigned = 0, capacity = 0 }
  state.game.jobs = { demolitions = {}, _nextId = 1 }
  state.ui.isBuildMenuOpen = false
  state.ui.isPlacingBuilding = true
  state.ui.selectedBuildingType = 'builder'
  state.ui._isFreeInitialBuilder = true
  state.ui._pauseTimeForInitial = true
  state.ui.isPaused = false
  state.ui.buildMenuAlpha = 0
  state.ui.previewT = 0
  state.ui.selectedBuilding = nil
  state.ui.isPlacingRoad = false
  state.ui.roadStartTile = nil
  state.ui.isVillagersPanelOpen = false
  state.ui._villagersPanelButtons = nil
  state.camera.x, state.camera.y = 0, 0
  state.time.t = state.time.dayLength * 0.25
  state.time.normalized = state.time.t / state.time.dayLength
  state.time.speed = 1
  state.time.lastIsDay = nil
  state.time.preNightSpeed = 1
  -- prompt instruction
  state.ui.promptText = "Place your Builders Workplace for free. Left-click a tile to place."
  state.ui.promptT = 0
  state.ui.promptDuration = 9999
  state.ui.promptSticky = false
end

return state 