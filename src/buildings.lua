-- buildings.lua
-- Placement rules, building rendering and radii drawing

local constants = require('src.constants')
local trees = require('src.trees')
local utils = require('src.utils')
local colors = constants.colors

local buildings = {}

function buildings.canAfford(state, buildingType)
  local def = state.buildingDefs[buildingType]
  if not def or not def.cost then return true end
  for resourceName, amount in pairs(def.cost) do
    local current = state.game.resources[resourceName] or 0
    if current < amount then return false end
  end
  return true
end

function buildings.payCost(state, buildingType)
  local def = state.buildingDefs[buildingType]
  if not def or not def.cost then return end
  for resourceName, amount in pairs(def.cost) do
    local current = state.game.resources[resourceName] or 0
    state.game.resources[resourceName] = math.max(0, current - amount)
  end
end

function buildings.canPlaceAt(state, tileX, tileY)
  local world = state.world
  if tileX < 0 or tileY < 0 or tileX >= world.tilesX or tileY >= world.tilesY then
    return false
  end
  for _, b in ipairs(state.game.buildings) do
    if b.tileX == tileX and b.tileY == tileY then
      return false
    end
  end
  if trees.getAt(state, tileX, tileY) then
    return false
  end
  return true
end

function buildings.place(state, buildingType, tileX, tileY)
  local color
  if buildingType == "house" then
    color = { 0.9, 0.6, 0.2, 1.0 }
  elseif buildingType == "lumberyard" then
    color = { 0.3, 0.7, 0.3, 1.0 }
  else
    color = { 0.7, 0.7, 0.7, 1.0 }
  end
  local newB = { type = buildingType, tileX = tileX, tileY = tileY, color = color }
  table.insert(state.game.buildings, newB)
  return newB
end

function buildings.drawAll(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, b in ipairs(state.game.buildings) do
    local px = b.tileX * TILE_SIZE
    local py = b.tileY * TILE_SIZE
    love.graphics.setColor(b.color)
    love.graphics.rectangle("fill", px, py, TILE_SIZE, TILE_SIZE, 4, 4)
    love.graphics.setColor(colors.outline)
    love.graphics.rectangle("line", px, py, TILE_SIZE, TILE_SIZE, 4, 4)
  end
end

function buildings.drawLumberyardRadii(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, b in ipairs(state.game.buildings) do
    if b.type == "lumberyard" then
      local def = state.buildingDefs.lumberyard
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

return buildings 