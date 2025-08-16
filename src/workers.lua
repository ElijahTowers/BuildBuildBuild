-- workers.lua
-- Worker AI: target acquisition, movement, chopping swing, delivery

local constants = require('src.constants')
local colors = constants.colors
local utils = require('src.utils')
local trees = require('src.trees')
local particles = require('src.particles')
local roads = require('src.roads')

local workers = {}

-- Capacity helpers
local function countWarehouses(state)
  local c = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' then c = c + 1 end
  end
  return c
end

-- Find a helpful nearby road tile center to steer toward
local function findRoadWaypoint(state, w, targetPx, targetPy)
  local TILE = constants.TILE_SIZE
  local wx, wy = w.x, w.y
  local workerTileX = math.floor(wx / TILE)
  local workerTileY = math.floor(wy / TILE)
  local bestCx, bestCy, bestScore
  local toTargetX, toTargetY = targetPx - wx, targetPy - wy
  local toTargetLen = math.max(1e-6, math.sqrt(toTargetX * toTargetX + toTargetY * toTargetY))
  local dirX, dirY = toTargetX / toTargetLen, toTargetY / toTargetLen
  local maxRadiusTiles = 1 -- only immediate neighborhood for cheap steering
  for dy = -maxRadiusTiles, maxRadiusTiles do
    for dx = -maxRadiusTiles, maxRadiusTiles do
      local tx = workerTileX + dx
      local ty = workerTileY + dy
      if roads.hasRoad(state, tx, ty) then
        local cx = tx * TILE + TILE / 2
        local cy = ty * TILE + TILE / 2
        local vx, vy = cx - wx, cy - wy
        local dist = math.sqrt(vx * vx + vy * vy)
        -- must be reasonably close
        if dist <= TILE * 0.9 then
          -- must be roughly in the direction of travel
          local dot = (vx * dirX + vy * dirY) / math.max(1e-6, dist)
          if dot > 0.1 then
            -- score favors closeness and alignment
            local score = dist / (dot + 0.1)
            if not bestScore or score < bestScore then
              bestScore = score
              bestCx, bestCy = cx, cy
            end
          end
        end
      end
    end
  end
  return bestCx, bestCy
end

local function computeWoodTotals(state)
  local base = state.game.resources.wood or 0
  local stored = 0
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' and b.storage and b.storage.wood then
      stored = stored + b.storage.wood
    end
  end
  return base, stored, base + stored
end

local function computeWoodCapacity(state)
  local baseCap = 50
  local whCap = 100 * countWarehouses(state)
  return baseCap + whCap
end

local function isWoodStorageFull(state)
  local _, _, total = computeWoodTotals(state)
  return total >= computeWoodCapacity(state)
end

-- Helpers restored after refactor
local function getTreeShakeOffset(t)
  return trees.getShakeOffset(t)
end

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

local function findNearestHouse(state, x, y)
  local best, bestDistSq
  bestDistSq = math.huge
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'house' or b.type == 'builder' then
      local d = (b.tileX - x) ^ 2 + (b.tileY - y) ^ 2
      if d < bestDistSq then
        bestDistSq = d
        best = b
      end
    end
  end
  return best
end

local function findNearestWarehouse(state, x, y)
  local best, bestDistSq
  bestDistSq = math.huge
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'warehouse' then
      local d = (b.tileX - x) ^ 2 + (b.tileY - y) ^ 2
      if d < bestDistSq then
        bestDistSq = d
        best = b
      end
    end
  end
  return best
end

local function findNearestBuilder(state, x, y)
  local best, bestDistSq
  bestDistSq = math.huge
  for _, b in ipairs(state.game.buildings) do
    if b.type == 'builder' then
      local d = (b.tileX - x) ^ 2 + (b.tileY - y) ^ 2
      if d < bestDistSq then
        bestDistSq = d
        best = b
      end
    end
  end
  return best
end

local function findConstructionTarget(state, bx, by)
  local best, bestDistSq
  bestDistSq = math.huge
  for _, tb in ipairs(state.game.buildings) do
    if tb.construction and not tb.construction.complete then
      local d = (tb.tileX - bx) ^ 2 + (tb.tileY - by) ^ 2
      if d < bestDistSq then
        bestDistSq = d
        best = tb
      end
    end
  end
  return best
end

-- Remove a persistent villager from global list
local function removeVillager(state, villager)
  if not villager then return end
  for i, v in ipairs(state.game.villagers) do
    if v == villager then
      table.remove(state.game.villagers, i)
      return
    end
  end
end

-- Auto-assign one worker to a worker building if there's free population and a free slot
local function autoAssignOneIfPossible(state, b)
  if not b or (b.type ~= 'lumberyard' and b.type ~= 'builder' and b.type ~= 'farm') then return end
  local def = state.buildingDefs[b.type]
  local free = (state.game.population.total or 0) - (state.game.population.assigned or 0)
  if free <= 0 then return end
  local maxSlots = def and def.numWorkers or 0
  if (b.assigned or 0) >= maxSlots then return end
  b.assigned = (b.assigned or 0) + 1
  state.game.population.assigned = (state.game.population.assigned or 0) + 1
  workers.spawnAssignedWorker(state, b)
end

-- Persistent villager creation
local function createVillager(state, homeB, workB, startX, startY)
  local v = {
    x = startX,
    y = startY,
    state = 'toWork', -- toWork, working, returning, atHome
    home = homeB,
    work = workB,
    carryWood = false,
    swingProgress = 0,
    swingHz = 1.8
  }
  table.insert(state.game.villagers, v)
  return v
end

function workers.spawnAssignedWorker(state, b)
  local TILE = constants.TILE_SIZE
  if b.type == 'lumberyard' then
    local home = findNearestHouse(state, b.tileX, b.tileY)
    local startX, startY
    if home then
      startX = home.tileX * TILE + TILE / 2
      startY = home.tileY * TILE + TILE / 2
    else
      startX = b.tileX * TILE + TILE / 2
      startY = b.tileY * TILE + TILE / 2
    end
    local v = createVillager(state, home, b, startX, startY)
    b.workers = b.workers or {}
    table.insert(b.workers, {
      x = startX,
      y = startY,
      state = 'toWork',
      targetTileX = nil,
      targetTileY = nil,
      targetTreeIndex = nil,
      carryWood = false,
      chopProgress = 0,
      swingProgress = 0,
      swingHz = 1.8,
      homeBuilding = home,
      villagerRef = v
    })
    return
  elseif b.type == 'builder' then
    local home = findNearestHouse(state, b.tileX, b.tileY)
    local startX, startY
    if home then
      startX = home.tileX * TILE + TILE / 2
      startY = home.tileY * TILE + TILE / 2
    else
      startX = b.tileX * TILE + TILE / 2
      startY = b.tileY * TILE + TILE / 2
    end
    local v = createVillager(state, home, b, startX, startY)
    b.workers = b.workers or {}
    table.insert(b.workers, {
      x = startX,
      y = startY,
      state = 'toWork',
      carryWood = false,
      swingProgress = 0,
      swingHz = 1.8,
      homeBuilding = home,
      villagerRef = v
    })
    return
  elseif b.type == 'farm' then
    local home = findNearestHouse(state, b.tileX, b.tileY)
    local startX, startY
    if home then
      startX = home.tileX * TILE + TILE / 2
      startY = home.tileY * TILE + TILE / 2
    else
      startX = b.tileX * TILE + TILE / 2
      startY = b.tileY * TILE + TILE / 2
    end
    local v = createVillager(state, home, b, startX, startY)
    b.workers = b.workers or {}
    table.insert(b.workers, {
      x = startX,
      y = startY,
      state = 'toWork',
      carryFood = false,
      harvestTimer = 0,
      homeBuilding = home,
      villagerRef = v,
      targetPlot = nil,
      plotPx = nil,
      plotPy = nil
    })
    return
  end
end

-- Ensure active worker list matches assigned; remove associated villager when shrinking
local function ensureWorkerCount(state, b)
  b.workers = b.workers or {}
  local desired = b.assigned or 0
  while #b.workers > desired do
    local removed = table.remove(b.workers)
    if removed and removed.villagerRef then
      removeVillager(state, removed.villagerRef)
    end
  end
  while #b.workers < desired do
    workers.spawnAssignedWorker(state, b)
  end
end

-- Movement with road bonus and steering
local function goTo(w, px, py, speed, dt, state)
  -- Optional steering to a nearby road tile when off-road
  local TILE = constants.TILE_SIZE
  local onRoad = roads.hasRoad(state, math.floor(w.x / TILE), math.floor(w.y / TILE))
  if not onRoad then
    if not w._waypoint or (math.abs(w._waypoint.x - w.x) + math.abs(w._waypoint.y - w.y)) < 2 then
      local rpx, rpy = findRoadWaypoint(state, w, px, py)
      if rpx and rpy then w._waypoint = { x = rpx, y = rpy } end
    end
    if w._waypoint then
      px, py = w._waypoint.x, w._waypoint.y
    end
  else
    w._waypoint = nil
  end

  local dx = px - w.x
  local dy = py - w.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1e-6 then
    return true
  end
  local vx = dx / dist
  local vy = dy / dist

  -- Road speed bonus if current tile is a road
  local tileX = math.floor(w.x / TILE)
  local tileY = math.floor(w.y / TILE)
  local mult = 1.0
  if state and roads.hasRoad(state, tileX, tileY) then
    mult = (state.game.roadSpeed and state.game.roadSpeed.onRoadMultiplier) or 1.5
    w._onRoad = true
    roads.markUsed(state, tileX, tileY)
  else
    w._onRoad = false
  end
  local arriveDist = math.max(2, speed * dt * 0.6)
  if dist <= arriveDist then
    w.x = px
    w.y = py
    if w._waypoint and math.abs(px - w._waypoint.x) + math.abs(py - w._waypoint.y) < 1 then
      -- reached steering waypoint; clear so next step heads to original target
      w._waypoint = nil
      return false
    end
    return true
  end
  w.x = w.x + vx * speed * mult * dt
  w.y = w.y + vy * speed * mult * dt
  return false
end

-- Update persistent villagers (movement and idle)
local function updateVillagers(state, dt)
  local isDay = (state.time.normalized >= 0.25 and state.time.normalized < 0.75)
  local TILE = constants.TILE_SIZE
  for _, v in ipairs(state.game.villagers) do
    local speed = 120
    if not isDay then
      local home = v.home
      if home then
        local hx = home.tileX * TILE + TILE / 2
        local hy = home.tileY * TILE + TILE / 2
        if goTo(v, hx, hy, speed, dt, state) then
          v.state = 'atHome'
        end
      end
    else
      if v.state == 'atHome' or v.state == 'toWork' then
        local work = v.work
        if work then
          local wx = work.tileX * TILE + TILE / 2
          local wy = work.tileY * TILE + TILE / 2
          if goTo(v, wx, wy, speed, dt, state) then
            v.state = 'working'
          else
            v.state = 'toWork'
          end
        end
      end
    end
  end
end

local function drawVillagers(state)
  if not state.ui.showWorldVillagerDots then return end
  for _, v in ipairs(state.game.villagers) do
    love.graphics.setColor(colors.worker)
    love.graphics.rectangle('fill', v.x - 4, v.y - 4, 8, 8, 2, 2)
    love.graphics.setColor(colors.outline)
    love.graphics.rectangle('line', v.x - 4, v.y - 4, 8, 8, 2, 2)
  end
end

local function takeDemolitionJob(state)
  local jobs = state.game.jobs and state.game.jobs.demolitions or nil
  if not jobs or #jobs == 0 then return nil end
  return table.remove(jobs, 1)
end

local function hasPendingDemolitions(state)
  local jobs = state.game.jobs and state.game.jobs.demolitions or nil
  return jobs and #jobs > 0
end

function workers.update(state, dt)
  local isDay = (state.time.normalized >= 0.25 and state.time.normalized < 0.75)
  updateVillagers(state, dt)
  for _, b in ipairs(state.game.buildings) do
    if b.type == "lumberyard" then
      ensureWorkerCount(state, b)
      local storageFull = isWoodStorageFull(state)
      if b.workers then
        for _, w in ipairs(b.workers) do
          local def = state.buildingDefs.lumberyard
          local TILE = constants.TILE_SIZE

          if not isDay then
            local home = w.homeBuilding
            if home then
              local hx = home.tileX * TILE + TILE / 2
              local hy = home.tileY * TILE + TILE / 2
              if goTo(w, hx, hy, def.workerSpeed, dt, state) then
                w.state = 'idle'
                w.targetTreeIndex = nil
                w.targetTileX, w.targetTileY = nil, nil
                w.carryWood = false
              end
            else
              local cx = b.tileX * TILE + TILE / 2
              local cy = b.tileY * TILE + TILE / 2
              goTo(w, cx, cy, def.workerSpeed, dt, state)
            end
            goto continue
          end

          if w.state == 'toWork' then
            local cx = b.tileX * TILE + TILE / 2
            local cy = b.tileY * TILE + TILE / 2
            if goTo(w, cx, cy, def.workerSpeed, dt, state) then
              w.state = 'idle'
            end
            goto continue
          end

          -- If storage full, stop working and idle at workplace
          if storageFull then
            local cx = b.tileX * TILE + TILE / 2
            local cy = b.tileY * TILE + TILE / 2
            goTo(w, cx, cy, def.workerSpeed * 0.5, dt, state)
            goto continue
          end

          if w.state == "idle" then
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
              local centerX = w.targetTileX * TILE + TILE / 2
              local centerY = w.targetTileY * TILE + TILE / 2
              local treeRadius = TILE * 0.4
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
              if goTo(w, targetPx, targetPy, def.workerSpeed, dt, state) then
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
              t.health = t.health - def.chopRate * dt
              w.chopProgress = w.chopProgress + def.chopRate * dt
              w.swingProgress = (w.swingProgress or 0) + dt * (w.swingHz or 1.8)
              if w.swingProgress >= 0.5 then
                w.swingProgress = w.swingProgress - 0.5
                local cx = w.targetTileX * TILE + TILE / 2
                local cy = w.targetTileY * TILE + TILE / 2
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
            local wh = findNearestWarehouse(state, math.floor(w.x / TILE), math.floor(w.y / TILE))
            local targetPx, targetPy
            if wh then
              targetPx = wh.tileX * TILE + TILE / 2
              targetPy = wh.tileY * TILE + TILE / 2
            else
              targetPx = b.tileX * TILE + TILE / 2
              targetPy = b.tileY * TILE + TILE / 2
            end
            if goTo(w, targetPx, targetPy, def.workerSpeed, dt, state) then
              if w.carryWood then
                local capacity = computeWoodCapacity(state)
                local base, stored, total = computeWoodTotals(state)
                local canAdd = math.max(0, capacity - total)
                if canAdd > 0 then
                  local add = math.min(canAdd, def.woodPerTree)
                  if wh then
                    wh.storage = wh.storage or {}
                    wh.storage.wood = (wh.storage.wood or 0) + add
                  else
                    state.game.resources.wood = (state.game.resources.wood or 0) + add
                    if countWarehouses(state) == 0 then
                      state.game.resources.wood = math.min(50, state.game.resources.wood)
                    end
                  end
                end
                w.carryWood = false
              end
              w.state = 'toWork'
              w.targetTreeIndex = nil
              w.targetTileX, w.targetTileY = nil, nil
            end
          end
          ::continue::
        end
      end
    elseif b.type == 'builder' then
      ensureWorkerCount(state, b)
      if b.workers then
        local def = state.buildingDefs.builder
        local speed = def.workerSpeed or 120
        local ratePerWorker = def.buildRate or 2.0
        local TILE = constants.TILE_SIZE
        for _, w in ipairs(b.workers) do
          if not isDay then
            local home = w.homeBuilding
            if home then
              local hx = home.tileX * TILE + TILE / 2
              local hy = home.tileY * TILE + TILE / 2
              goTo(w, hx, hy, speed, dt, state)
            end
            w.mode = nil
            w.targetBuilding = nil
            w.demolishing = nil
            w.demoTimer = nil
          else
            -- Prefer demolition job if queued
            if not w.demolishing and hasPendingDemolitions(state) then
              local job = takeDemolitionJob(state)
              if job and job.target then
                w.demolishing = job
                w.targetBuilding = job.target
              end
            end

            if w.demolishing and w.targetBuilding then
              local tb = w.targetBuilding
              local tx = tb.tileX * TILE + TILE / 2
              local ty = tb.tileY * TILE + TILE / 2
              if goTo(w, tx, ty, speed, dt, state) then
                w.demoTimer = (w.demoTimer or 0) + dt
                -- small particle hint while demolishing
                if (w.demoTimer or 0) > 0.2 then
                  particles.spawnDustBurst(state.game.particles, tx, ty)
                  w.demoTimer = 0
                end
                -- finish quickly
                if (w._demoElapsed or 0) >= 1.2 then
                  -- perform demolish
                  require('src.buildings').demolish(state, tb)
                  w.demolishing = nil
                  w._demoElapsed = 0
                else
                  w._demoElapsed = (w._demoElapsed or 0) + dt
                end
              end
            else
              -- normal building work
              if not w.targetBuilding or (w.targetBuilding.construction and w.targetBuilding.construction.complete) then
                w.targetBuilding = findConstructionTarget(state, b.tileX, b.tileY)
              end
              if w.targetBuilding then
                local tx = w.targetBuilding.tileX * TILE + TILE / 2
                local ty = w.targetBuilding.tileY * TILE + TILE / 2
                if goTo(w, tx, ty, speed, dt, state) then
                  local c = w.targetBuilding.construction
                  if c and not c.complete then
                    c.progress = math.min(c.required, (c.progress or 0) + ratePerWorker * dt)
                    if c.progress >= c.required then
                      c.complete = true
                      if w.targetBuilding.type == 'house' then
                        local cap = (state.buildingDefs.house.residents or 0)
                        state.game.population.total = (state.game.population.total or 0) + cap
                      elseif w.targetBuilding.type == 'builder' then
                        local cap = (state.buildingDefs.builder.residents or 0)
                        state.game.population.total = (state.game.population.total or 0) + cap
                      end
                      autoAssignOneIfPossible(state, w.targetBuilding)
                    end
                  end
                end
              else
                local cx = b.tileX * TILE + TILE / 2
                local cy = b.tileY * TILE + TILE / 2
                goTo(w, cx, cy, speed * 0.5, dt, state)
              end
            end
          end
        end
      end
    elseif b.type == 'farm' then
      ensureWorkerCount(state, b)
      if b.workers and b.construction and b.construction.complete then
        local def = state.buildingDefs.farm
        local TILE = constants.TILE_SIZE
        for _, w in ipairs(b.workers) do
          local speed = def.workerSpeed or 120
          if not isDay then
            local home = w.homeBuilding
            if home then
              local hx = home.tileX * TILE + TILE / 2
              local hy = home.tileY * TILE + TILE / 2
              goTo(w, hx, hy, speed, dt, state)
            end
            w.state = 'idle'
            w.harvestTimer = 0
            w.carryFood = false
            w.targetPlot = nil
            w.plotPx, w.plotPy = nil, nil
          else
            if w.state == 'toWork' or w.state == 'idle' or w.state == 'choosePlot' then
              -- pick a random surrounding plot and walk there
              if not w.targetPlot then
                local plots = (b.farm and b.farm.plots) or {}
                if #plots > 0 then
                  local p = plots[love.math.random(1, #plots)]
                  w.targetPlot = p
                  local jitterX = love.math.random(-6, 6)
                  local jitterY = love.math.random(-6, 6)
                  w.plotPx = (b.tileX + p.dx) * TILE + TILE / 2 + jitterX
                  w.plotPy = (b.tileY + p.dy) * TILE + TILE / 2 + jitterY
                else
                  -- fallback to center
                  w.plotPx = b.tileX * TILE + TILE / 2
                  w.plotPy = b.tileY * TILE + TILE / 2
                end
              end
              local tx = w.plotPx or (b.tileX * TILE + TILE / 2)
              local ty = w.plotPy or (b.tileY * TILE + TILE / 2)
              if goTo(w, tx, ty, speed, dt, state) then
                w.state = 'harvesting'
                w.harvestTimer = 0
              else
                w.state = 'toWork'
              end
            elseif w.state == 'harvesting' then
              w.harvestTimer = (w.harvestTimer or 0) + dt
              if w.harvestTimer >= (def.harvestTime or 2.5) then
                w.harvestTimer = 0
                w.carryFood = true
                w.state = 'deliverFood'
              end
            elseif w.state == 'deliverFood' then
              local wh = findNearestWarehouse(state, math.floor(w.x / TILE), math.floor(w.y / TILE))
              local tx, ty
              local drop = wh or findNearestBuilder(state, math.floor(w.x / TILE), math.floor(w.y / TILE))
              if drop then
                tx = drop.tileX * TILE + TILE / 2
                ty = drop.tileY * TILE + TILE / 2
              else
                tx = b.tileX * TILE + TILE / 2
                ty = b.tileY * TILE + TILE / 2
              end
              if goTo(w, tx, ty, speed, dt, state) then
                if w.carryFood then
                  local amount = (def.harvestPerTrip or 4)
                  if wh then
                    wh.storage = wh.storage or {}
                    wh.storage.food = (wh.storage.food or 0) + amount
                  else
                    local builderB = findNearestBuilder(state, math.floor(w.x / TILE), math.floor(w.y / TILE))
                    if builderB then
                      builderB.storage = builderB.storage or {}
                      builderB.storage.food = (builderB.storage.food or 0) + amount
                    else
                      state.game.resources.food = (state.game.resources.food or 0) + amount
                    end
                  end
                  w.carryFood = false
                end
                -- pick a new plot next
                w.targetPlot = nil
                w.plotPx, w.plotPy = nil, nil
                w.state = 'choosePlot'
              end
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
        -- on-road streak
        if w._onRoad then
          love.graphics.setColor(1, 1, 1, 0.15)
          love.graphics.rectangle('fill', w.x - 6, w.y + 7, 12, 2, 1, 1)
        end
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
    elseif b.type == 'builder' and b.workers then
      for _, w in ipairs(b.workers) do
        if w._onRoad then
          love.graphics.setColor(1, 1, 1, 0.15)
          love.graphics.rectangle('fill', w.x - 6, w.y + 7, 12, 2, 1, 1)
        end
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.ellipse('fill', w.x, w.y + 6, 7, 3)
        love.graphics.setColor(colors.worker)
        love.graphics.rectangle("fill", w.x - 5, w.y - 5, 10, 10, 2, 2)
        love.graphics.setColor(colors.outline)
        love.graphics.rectangle("line", w.x - 5, w.y - 5, 10, 10, 2, 2)
      end
    elseif b.type == 'farm' and b.workers then
      for _, w in ipairs(b.workers) do
        if w._onRoad then
          love.graphics.setColor(1, 1, 1, 0.15)
          love.graphics.rectangle('fill', w.x - 6, w.y + 7, 12, 2, 1, 1)
        end
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.ellipse('fill', w.x, w.y + 6, 7, 3)
        love.graphics.setColor(colors.worker)
        love.graphics.rectangle("fill", w.x - 5, w.y - 5, 10, 10, 2, 2)
        love.graphics.setColor(colors.outline)
        love.graphics.rectangle("line", w.x - 5, w.y - 5, 10, 10, 2, 2)
        if w.carryFood then
          love.graphics.setColor(0.95, 0.85, 0.3, 1)
          love.graphics.rectangle('fill', w.x - 3, w.y - 12, 6, 4)
        end
        if w.state == 'harvesting' then
          -- simple hoeing motion over a surrounding plot
          local t = (w.harvestTimer or 0) % 0.5
          local phase = t / 0.5
          local angle = -0.6 + phase * 1.2
          local len = 12
          love.graphics.setColor(colors.outline)
          love.graphics.setLineWidth(2)
          love.graphics.line(w.x, w.y, w.x + math.cos(angle) * len, w.y + math.sin(angle) * len)
          love.graphics.setLineWidth(1)
        end
      end
    end
  end
  drawVillagers(state)
end

return workers 