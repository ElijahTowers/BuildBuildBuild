-- state.lua
-- Central game state: resources, camera, world size, building definitions

local constants = require('src.constants')

local state = {}

-- Camera and world limits
state.camera = { x = 0, y = 0, panSpeed = 700 }
state.world = { tilesX = 0, tilesY = 0 }

-- UI state
state.ui = {
  isBuildMenuOpen = false,
  isPlacingBuilding = false,
  selectedBuildingType = nil,
  isPaused = false
}

-- Resources and buildings
state.game = {
  resources = { wood = 50 },
  productionRates = { wood = 0 },
  buildings = {},
  trees = {},
  particles = {}
}

-- Building definitions and balance
state.buildingDefs = {
  house = {
    cost = { wood = 10 },
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
  state.game.resources = { wood = 50 }
  state.game.productionRates = { wood = 0 }
  state.ui.isBuildMenuOpen = false
  state.ui.isPlacingBuilding = false
  state.ui.selectedBuildingType = nil
  state.ui.isPaused = false
  state.camera.x, state.camera.y = 0, 0
end

return state 