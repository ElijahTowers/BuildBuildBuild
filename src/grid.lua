-- grid.lua
-- Draws the tile grid only for the visible camera window

local constants = require('src.constants')
local colors = constants.colors

local grid = {}

function grid.draw(state)
  local TILE_SIZE = constants.TILE_SIZE
  local camera = state.camera
  local world = state.world
  local screenW, screenH = love.graphics.getDimensions()
  local startTileX = math.max(0, math.floor(camera.x / TILE_SIZE))
  local endTileX = math.min(world.tilesX, math.ceil((camera.x + screenW) / TILE_SIZE))
  local startTileY = math.max(0, math.floor(camera.y / TILE_SIZE))
  local endTileY = math.min(world.tilesY, math.ceil((camera.y + screenH) / TILE_SIZE))

  love.graphics.setColor(colors.grid)
  for tx = startTileX, endTileX do
    local x = tx * TILE_SIZE
    love.graphics.line(x, startTileY * TILE_SIZE, x, endTileY * TILE_SIZE)
  end
  for ty = startTileY, endTileY do
    local y = ty * TILE_SIZE
    love.graphics.line(startTileX * TILE_SIZE, y, endTileX * TILE_SIZE, y)
  end
end

return grid 