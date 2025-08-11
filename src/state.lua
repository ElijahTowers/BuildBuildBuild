-- state.lua
-- Central game state: resources, camera, world size, building definitions

local constants = require('src.constants')

local state = {}

-- Camera and world limits
state.camera = { x = 0, y = 0, panSpeed = 700 }
state.world = { tilesX = 0, tilesY = 0 }

-- Time of day
state.time = {
  t = 0,           -- seconds elapsed in current day
  dayLength = 180, -- seconds per full day-night cycle
  normalized = 0   -- 0..1 across the day
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
  _villagersPanelButtons = nil -- temp bounds for assign/unassign in panel
}

-- Resources, population and world entities
state.game = {
  resources = { wood = 50 },
  productionRates = { wood = 0 },
  population = { total = 0, assigned = 0, capacity = 0 },
  buildings = {},
  trees = {},
  particles = {},
  roads = {}, -- map of road tiles
  villagers = {} -- persistent villager entities
}

-- Building definitions and balance
state.buildingDefs = {
  house = {
    cost = { wood = 10 },
    residents = 3,
    production = nil
  },
  lumberyard = {
    cost = { wood = 20 },
    production = nil,
    radiusTiles = 6,
    chopRate = 1.0,
    woodPerTree = 6,
    numWorkers = 2,
    workerSpeed = 120 -- pixels per second
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
  state.game.resources = { wood = 50 }
  state.game.productionRates = { wood = 0 }
  state.game.population = { total = 0, assigned = 0, capacity = 0 }
  state.ui.isBuildMenuOpen = false
  state.ui.isPlacingBuilding = false
  state.ui.selectedBuildingType = nil
  state.ui.isPaused = false
  state.ui.buildMenuAlpha = 0
  state.ui.previewT = 0
  state.ui.selectedBuilding = nil
  state.ui.isPlacingRoad = false
  state.ui.roadStartTile = nil
  state.ui.isVillagersPanelOpen = false
  state.ui._villagersPanelButtons = nil
  state.camera.x, state.camera.y = 0, 0
  state.time.t = 0
  state.time.normalized = 0
end

return state 