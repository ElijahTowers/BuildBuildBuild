-- particles.lua
-- Leaf particle system for visual feedback (tree falls)

local constants = require('src.constants')
local colors = constants.colors

local particles = {}

function particles.spawnLeafBurst(gameParticles, tileX, tileY)
  local TILE_SIZE = constants.TILE_SIZE
  local cx = tileX * TILE_SIZE + TILE_SIZE / 2
  local cy = tileY * TILE_SIZE + TILE_SIZE / 2
  for i = 1, 24 do
    local angle = math.random() * math.pi * 2
    local speed = 40 + math.random() * 100
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed
    table.insert(gameParticles, {
      x = cx,
      y = cy,
      vx = vx,
      vy = vy,
      life = 0.8 + math.random() * 0.6,
      age = 0,
      size = 2 + math.random() * 2,
      color = { colors.particleLeaf[1], colors.particleLeaf[2], colors.particleLeaf[3], colors.particleLeaf[4] }
    })
  end
end

function particles.spawnDustBurst(gameParticles, px, py)
  for i = 1, 18 do
    local angle = math.random() * math.pi * 2
    local speed = 30 + math.random() * 80
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed
    table.insert(gameParticles, {
      x = px,
      y = py,
      vx = vx,
      vy = vy,
      life = 0.5 + math.random() * 0.4,
      age = 0,
      size = 1.5 + math.random() * 2,
      color = { 0.7, 0.6, 0.45, 0.9 }
    })
  end
end

function particles.spawnSawdust(gameParticles, px, py, dirX, dirY)
  for i = 1, 12 do
    local angle = math.atan2(dirY, dirX) + (math.random() - 0.5) * 0.6
    local speed = 40 + math.random() * 60
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed
    table.insert(gameParticles, {
      x = px,
      y = py,
      vx = vx,
      vy = vy,
      life = 0.4 + math.random() * 0.3,
      age = 0,
      size = 1 + math.random() * 1.5,
      color = { 0.8, 0.7, 0.5, 0.9 }
    })
  end
end

function particles.update(gameParticles, dt)
  for i = #gameParticles, 1, -1 do
    local p = gameParticles[i]
    p.age = p.age + dt
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vy = p.vy + 60 * dt -- gravity
    if p.age >= p.life then
      table.remove(gameParticles, i)
    end
  end
end

function particles.draw(gameParticles)
  for _, p in ipairs(gameParticles) do
    local alpha = 1 - (p.age / p.life)
    love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
    love.graphics.rectangle("fill", p.x - p.size / 2, p.y - p.size / 2, p.size, p.size)
  end
end

return particles 