-- workers.lua
-- Worker AI: target acquisition, movement, chopping swing, delivery

local constants = require('src.constants')
local colors = constants.colors
local utils = require('src.utils')
local trees = require('src.trees')
local particles = require('src.particles')

local workers = {}

-- Compute tree shake offset (reuse trees function)
local function getTreeShakeOffset(t)
  return trees.getShakeOffset(t)
end

-- Compute max axe length to avoid drawing over the tree canopy
local function computeMaxAxeLength(wx, wy, angle, cx, cy, radius, maxArmLen, gap)
  local ux, uy = math.cos(angle), math.sin(angle)
  local dx = wx - cx
  local dy = wy - cy
  local b = 2 * (ux * dx + uy * dy)
  local c = dx * dx + dy * dy - radius * radius
  local disc = b * b - 4 * c
  if disc <= 0 then return maxArmLen end
  local sqrtDisc = math.sqrt(disc)
  local t1 = (-b - sqrtDisc) / 2
  local t2 = (-b + sqrtDisc) / 2
  local tHit
  if t1 >= 0 then tHit = t1 elseif t2 >= 0 then tHit = t2 end
  if not tHit then return maxArmLen end
  local len = math.min(maxArmLen, tHit - (gap or 2))
  if len < 0 then len = 0 end
  return len
end

function workers.spawnForLumberyard(state, b)
  local def = state.buildingDefs.lumberyard
  b.workers = b.workers or {}
  local TILE_SIZE = constants.TILE_SIZE
  local cx = b.tileX * TILE_SIZE + TILE_SIZE / 2
  local cy = b.tileY * TILE_SIZE + TILE_SIZE / 2
  local desired = b.assigned or 0
  for i = #b.workers + 1, desired do
    table.insert(b.workers, {
      x = cx + (i - 1) * 6 - 6,
      y = cy,
      state = "idle",
      targetTileX = nil,
      targetTileY = nil,
      targetTreeIndex = nil,
      carryWood = false,
      chopProgress = 0,
      swingProgress = 0,
      swingHz = 1.8
    })
  end
end

local function ensureWorkerCount(state, b)
  b.workers = b.workers or {}
  local desired = b.assigned or 0
  -- Trim extra workers
  while #b.workers > desired do
    table.remove(b.workers)
  end
  -- Spawn missing workers
  workers.spawnForLumberyard(state, b)
end

local function acquireTreeForWorker(state, b, w)
  local def = state.buildingDefs.lumberyard
  local bestIndex, bestDistSq
  bestDistSq = math.huge
  for index, t in ipairs(state.game.trees) do
    if t.alive and not t.reserved then
      local distSq = utils.distanceSq(b.tileX, b.tileY, t.tileX, t.tileY)
      if distSq <= (def.radiusTiles * def.radiusTiles) and distSq < bestDistSq then
        bestDistSq = distSq
        bestIndex = index
      end
    end
  end
  if bestIndex then
    local t = state.game.trees[bestIndex]
    t.reserved = true
    t.beingChopped = true
    w.targetTreeIndex = bestIndex
    w.targetTileX = t.tileX
    w.targetTileY = t.tileY
    w.state = "toTree"
  else
    w.state = "idle"
  end
end

local function updateWorker(state, b, w, dt)
  local def = state.buildingDefs.lumberyard
  local TILE_SIZE = constants.TILE_SIZE
  local function goTo(px, py)
    local dx = px - w.x
    local dy = py - w.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 2 then
      w.x = px
      w.y = py
      return true
    end
    local vx = dx / (dist + 1e-6)
    local vy = dy / (dist + 1e-6)
    w.x = w.x + vx * def.workerSpeed * dt
    w.y = w.y + vy * def.workerSpeed * dt
    return false
  end

  if w.state == "idle" then
    acquireTreeForWorker(state, b, w)

  elseif w.state == "toTree" then
    local t = state.game.trees[w.targetTreeIndex]
    if not t or not t.alive then
      w.state = "idle"
      if t then t.reserved = false; t.beingChopped = false; t.shakeTime = 0 end
      w.targetTreeIndex = nil
      return
    end
    local centerX = w.targetTileX * TILE_SIZE + TILE_SIZE / 2
    local centerY = w.targetTileY * TILE_SIZE + TILE_SIZE / 2
    local treeRadius = TILE_SIZE * 0.4
    local approachMargin = 12
    local approachDist = treeRadius + approachMargin
    local dirX = centerX - w.x
    local dirY = centerY - w.y
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    if len < 1 then len = 1 end
    dirX = dirX / len
    dirY = dirY / len
    local targetPx = centerX - dirX * approachDist
    local targetPy = centerY - dirY * approachDist

    if goTo(targetPx, targetPy) then
      w.state = "chopping"
      w.chopProgress = 0
      w.swingProgress = 0
    end

  elseif w.state == "chopping" then
    local t = state.game.trees[w.targetTreeIndex]
    if not t or not t.alive then
      w.state = "idle"
      if t then t.reserved = false; t.beingChopped = false; t.shakeTime = 0 end
      w.targetTreeIndex = nil
      return
    end

    t.health = t.health - def.chopRate * dt
    w.chopProgress = w.chopProgress + def.chopRate * dt

    w.swingProgress = (w.swingProgress or 0) + dt * (w.swingHz or 1.8)
    if w.swingProgress >= 0.5 then
      w.swingProgress = w.swingProgress - 0.5
      local cx = w.targetTileX * TILE_SIZE + TILE_SIZE / 2
      local cy = w.targetTileY * TILE_SIZE + TILE_SIZE / 2
      local dirX = cx - w.x
      local dirY = cy - w.y
      local len = math.sqrt(dirX * dirX + dirY * dirY)
      if len > 0 then dirX = dirX / len; dirY = dirY / len end
      t.shakeDirX, t.shakeDirY = dirX, dirY
      t.shakePower = math.min(4.0, (t.shakePower or 0) + 1.6)
      t.shakeTime = 0
      particles.spawnSawdust(state.game.particles, cx, cy, dirX, dirY)
    end

    if t.health <= 0 then
      t.alive = false
      t.reserved = false
      t.beingChopped = false
      t.shakeTime = 0
      particles.spawnLeafBurst(state.game.particles, w.targetTileX, w.targetTileY)
      w.carryWood = true
      w.state = "returning"
    end

  elseif w.state == "returning" then
    local homePx = b.tileX * TILE_SIZE + TILE_SIZE / 2
    local homePy = b.tileY * TILE_SIZE + TILE_SIZE / 2
    if goTo(homePx, homePy) then
      if w.carryWood then
        state.game.resources.wood = (state.game.resources.wood or 0) + def.woodPerTree
        w.carryWood = false
      end
      w.state = "idle"
      w.targetTreeIndex = nil
      w.targetTileX, w.targetTileY = nil, nil
    end
  end
end

function workers.update(state, dt)
  for _, b in ipairs(state.game.buildings) do
    if b.type == "lumberyard" then
      ensureWorkerCount(state, b)
      if b.workers then
        for _, w in ipairs(b.workers) do
          -- update each active worker
          local def = state.buildingDefs.lumberyard
          local TILE_SIZE = constants.TILE_SIZE
          local function goTo(px, py)
            local dx = px - w.x
            local dy = py - w.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 2 then
              w.x = px
              w.y = py
              return true
            end
            local vx = dx / (dist + 1e-6)
            local vy = dy / (dist + 1e-6)
            w.x = w.x + vx * def.workerSpeed * dt
            w.y = w.y + vy * def.workerSpeed * dt
            return false
          end

          if w.state == "idle" then
            -- acquire tree
            local bestIndex, bestDistSq
            bestDistSq = math.huge
            for index, t in ipairs(state.game.trees) do
              if t.alive and not t.reserved then
                local distSq = (b.tileX - t.tileX) ^ 2 + (b.tileY - t.tileY) ^ 2
                if distSq <= (state.buildingDefs.lumberyard.radiusTiles ^ 2) and distSq < bestDistSq then
                  bestDistSq = distSq
                  bestIndex = index
                end
              end
            end
            if bestIndex then
              local t = state.game.trees[bestIndex]
              t.reserved = true
              t.beingChopped = true
              w.targetTreeIndex = bestIndex
              w.targetTileX = t.tileX
              w.targetTileY = t.tileY
              w.state = "toTree"
            end

          elseif w.state == "toTree" then
            local t = state.game.trees[w.targetTreeIndex]
            if not t or not t.alive then
              w.state = "idle"
              if t then t.reserved = false; t.beingChopped = false; t.shakeTime = 0 end
            else
              local centerX = w.targetTileX * TILE_SIZE + TILE_SIZE / 2
              local centerY = w.targetTileY * TILE_SIZE + TILE_SIZE / 2
              local treeRadius = TILE_SIZE * 0.4
              local approachMargin = 12
              local approachDist = treeRadius + approachMargin
              local dirX = centerX - w.x
              local dirY = centerY - w.y
              local len = math.sqrt(dirX * dirX + dirY * dirY)
              if len < 1 then len = 1 end
              dirX = dirX / len
              dirY = dirY / len
              local targetPx = centerX - dirX * approachDist
              local targetPy = centerY - dirY * approachDist
              if goTo(targetPx, targetPy) then
                w.state = "chopping"
                w.chopProgress = 0
                w.swingProgress = 0
              end
            end

          elseif w.state == "chopping" then
            local t = state.game.trees[w.targetTreeIndex]
            if not t or not t.alive then
              w.state = "idle"
              if t then t.reserved = false; t.beingChopped = false; t.shakeTime = 0 end
            else
              t.health = t.health - state.buildingDefs.lumberyard.chopRate * dt
              w.chopProgress = w.chopProgress + state.buildingDefs.lumberyard.chopRate * dt
              w.swingProgress = (w.swingProgress or 0) + dt * (w.swingHz or 1.8)
              if w.swingProgress >= 0.5 then
                w.swingProgress = w.swingProgress - 0.5
                local cx = w.targetTileX * TILE_SIZE + TILE_SIZE / 2
                local cy = w.targetTileY * TILE_SIZE + TILE_SIZE / 2
                local dirX = cx - w.x
                local dirY = cy - w.y
                local len = math.sqrt(dirX * dirX + dirY * dirY)
                if len > 0 then dirX = dirX / len; dirY = dirY / len end
                t.shakeDirX, t.shakeDirY = dirX, dirY
                t.shakePower = math.min(4.0, (t.shakePower or 0) + 1.6)
                t.shakeTime = 0
                particles.spawnSawdust(state.game.particles, cx, cy, dirX, dirY)
              end
              if t.health <= 0 then
                t.alive = false
                t.reserved = false
                t.beingChopped = false
                t.stumpTime = 3.0
                particles.spawnLeafBurst(state.game.particles, w.targetTileX, w.targetTileY)
                w.carryWood = true
                w.state = "returning"
              end
            end

          elseif w.state == "returning" then
            local homePx = b.tileX * TILE_SIZE + TILE_SIZE / 2
            local homePy = b.tileY * TILE_SIZE + TILE_SIZE / 2
            if goTo(homePx, homePy) then
              if w.carryWood then
                state.game.resources.wood = (state.game.resources.wood or 0) + state.buildingDefs.lumberyard.woodPerTree
                w.carryWood = false
              end
              w.state = "idle"
              w.targetTreeIndex = nil
              w.targetTileX, w.targetTileY = nil, nil
            end
          end
        end
      end
    end
  end
end

function workers.draw(state)
  local TILE_SIZE = constants.TILE_SIZE
  for _, b in ipairs(state.game.buildings) do
    if b.type == "lumberyard" and b.workers then
      for _, w in ipairs(b.workers) do
        -- Soft shadow
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.ellipse('fill', w.x, w.y + 6, 7, 3)

        love.graphics.setColor(colors.worker)
        love.graphics.rectangle("fill", w.x - 5, w.y - 5, 10, 10, 2, 2)
        love.graphics.setColor(colors.outline)
        love.graphics.rectangle("line", w.x - 5, w.y - 5, 10, 10, 2, 2)
        if w.carryWood then
          love.graphics.setColor(colors.workerCarry)
          love.graphics.rectangle("fill", w.x - 3, w.y - 12, 6, 4)
        end
        if w.state == "chopping" and w.targetTileX and w.targetTileY then
          local t = state.game.trees[w.targetTreeIndex]
          local tx = w.targetTileX * TILE_SIZE + TILE_SIZE / 2
          local ty = w.targetTileY * TILE_SIZE + TILE_SIZE / 2
          local sx, sy = 0, 0
          if t then sx, sy = getTreeShakeOffset(t) end
          local cx, cy = tx + sx, ty + sy
          local baseAngle = math.atan2(cy - w.y, cx - w.x)
          local swingArc = 0.6
          local forward = math.min((w.swingProgress or 0) * 2, 1)
          local angle = baseAngle - swingArc + forward * swingArc
          local armLen = 18
          local radius = TILE_SIZE * 0.4
          local maxLen = computeMaxAxeLength(w.x, w.y, angle, cx, cy, radius, armLen, 2)
          local ax = w.x + math.cos(angle) * maxLen
          local ay = w.y + math.sin(angle) * maxLen
          love.graphics.setColor(colors.outline)
          love.graphics.setLineWidth(2)
          love.graphics.line(w.x, w.y, ax, ay)
          love.graphics.setLineWidth(1)

          love.graphics.setColor(colors.choppingRing)
          love.graphics.circle("line", tx, ty, TILE_SIZE * 0.55)
        end
      end
    end
  end
end

return workers 