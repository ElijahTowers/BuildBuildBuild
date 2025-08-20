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
      color = { colors.particleLeaf[1], colors.particleLeaf[2], colors.particleLeaf[3], colors.particleLeaf[4] },
      g = 60
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
      color = { 0.7, 0.6, 0.45, 0.9 },
      g = 60
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
      color = { 0.8, 0.7, 0.5, 0.9 },
      g = 60
    })
  end
end

function particles.spawnSmokePuff(gameParticles, px, py)
  for i = 1, 8 do
    local angle = (math.random() - 0.5) * 0.8
    local speed = 15 + math.random() * 20
    local vx = math.cos(angle) * speed * 0.5
    local vy = - (20 + math.random() * 25)
    table.insert(gameParticles, {
      x = px,
      y = py,
      vx = vx,
      vy = vy,
      life = 0.9 + math.random() * 0.5,
      age = 0,
      size = 2 + math.random() * 3,
      color = { 0.7, 0.7, 0.7, 0.8 },
      g = 20
    })
  end
end

function particles.spawnFoodPickup(gameParticles, px, py)
  for i = 1, 8 do
    local angle = math.random() * math.pi * 2
    local speed = 20 + math.random() * 40
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed
    table.insert(gameParticles, {
      x = px,
      y = py,
      vx = vx,
      vy = vy,
      life = 0.35 + math.random() * 0.25,
      age = 0,
      size = 1.5 + math.random() * 1.5,
      color = { 0.95, 0.85, 0.3, 1.0 },
      g = 30
    })
  end
end

function particles.spawnConfetti(gameParticles, px, py)
  for i = 1, 36 do
    local angle = math.random() * math.pi * 2
    local speed = 60 + math.random() * 120
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed
    local palette = {
      {0.95, 0.35, 0.35, 1.0}, {0.35, 0.8, 0.45, 1.0}, {0.35, 0.55, 0.95, 1.0},
      {0.95, 0.85, 0.3, 1.0}, {0.85, 0.35, 0.9, 1.0}
    }
    local c = palette[math.random(1, #palette)]
    table.insert(gameParticles, {
      x = px,
      y = py,
      vx = vx,
      vy = vy,
      life = 0.8 + math.random() * 0.7,
      age = 0,
      size = 2 + math.random() * 2,
      color = { c[1], c[2], c[3], c[4] },
      g = 90
    })
  end
end

function particles.update(gameParticles, dt)
  for i = #gameParticles, 1, -1 do
    local p = gameParticles[i]
    p.age = p.age + dt
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vy = p.vy + (p.g or 60) * dt
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