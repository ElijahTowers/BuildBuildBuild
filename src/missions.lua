-- missions.lua
-- Simple mission system: defines and evaluates the first mission

local missions = {}

local function computeTotalWood(state)
	local total = (state.game.resources and state.game.resources.wood) or 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'warehouse' and b.storage and b.storage.wood then
			total = total + b.storage.wood
		end
	end
	return total
end

local function countCompletedBuildings(state, typ)
	local c = 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == typ and (not b.construction or b.construction.complete) then c = c + 1 end
	end
	return c
end

local function sumAssignedLumberyardWorkers(state)
	local sum = 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'lumberyard' and (not b.construction or b.construction.complete) then
			sum = sum + (b.assigned or 0)
		end
	end
	return sum
end

local function maxAssignedInSingleLumberyard(state)
	local maxv = 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'lumberyard' and (not b.construction or b.construction.complete) then
			if (b.assigned or 0) > maxv then maxv = (b.assigned or 0) end
		end
	end
	return maxv
end

local function countRoadTiles(state)
	local n = 0
	for _, _ in pairs(state.game.roads or {}) do n = n + 1 end
	return n
end

-- Food helpers
local function computeTotalMarketFood(state)
	local total = 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'market' and b.storage and b.storage.food then
			total = total + b.storage.food
		end
	end
	return total
end

local function sumAssignedBuilders(state)
	local sum = 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'builder' and (not b.construction or b.construction.complete) then
			sum = sum + (b.assigned or 0)
		end
	end
	return sum
end

local function computeLivingTrees(state)
	local c = 0
	for _, t in ipairs(state.game.trees or {}) do if t.alive then c = c + 1 end end
	return c
end

local function computeWoodCapacity(state)
	local cap = 50
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'warehouse' and b.construction and b.construction.complete then cap = cap + 100 end
	end
	return cap
end

local function hasRoad(state, x, y)
	local k = x .. "," .. y
	return (state.game.roads and state.game.roads[k]) ~= nil
end

-- Count completed houses that are adjacent to at least one road tile
local function countHousesConnectedByRoad(state)
  local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
  local count = 0
  for _, h in ipairs(state.game.buildings or {}) do
    if h.type == 'house' and (not h.construction or h.construction.complete) then
      local connected = false
      for i=1,4 do
        local nx, ny = h.tileX + dirs[i][1], h.tileY + dirs[i][2]
        if hasRoad(state, nx, ny) then connected = true; break end
      end
      if connected then count = count + 1 end
    end
  end
  return count
end

-- Road connectivity between two buildings via adjacent road tiles
local function roadConnectedBetweenBuildings(state, b1, b2)
	if not b1 or not b2 then return false end
	local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
	local function adjRoadTiles(x, y)
		local list = {}
		for i=1,4 do
			local nx, ny = x + dirs[i][1], y + dirs[i][2]
			if hasRoad(state, nx, ny) then table.insert(list, { nx, ny }) end
		end
		return list
	end
	local start = adjRoadTiles(b1.tileX, b1.tileY)
	local goals = {}
	for _, t in ipairs(adjRoadTiles(b2.tileX, b2.tileY)) do
		goals[t[1] .. "," .. t[2]] = true
	end
	if #start == 0 or (next(goals) == nil) then return false end
	local K = function(x,y) return x .. "," .. y end
	local q = {}
	for _, s in ipairs(start) do table.insert(q, s) end
	local head = 1
	local visited = {}
	for _, s in ipairs(start) do visited[K(s[1], s[2])] = true end
	while q[head] do
		local cx, cy = q[head][1], q[head][2]
		head = head + 1
		if goals[K(cx, cy)] then return true end
		for i=1,4 do
			local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
			if hasRoad(state, nx, ny) and not visited[K(nx, ny)] then
				visited[K(nx, ny)] = true
				table.insert(q, { nx, ny })
			end
		end
	end
	return false
end

-- Check for a Builder's Workplace at least 50 tiles from the first one, road-connected
local function frontierOutpostAchieved(state)
	local firstBuilder = nil
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'builder' and (not b.construction or b.construction.complete) then
			firstBuilder = b; break
		end
	end
	if not firstBuilder then return false end
	local threshold = 50
	local thresholdSq = threshold * threshold
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'builder' and b ~= firstBuilder and (not b.construction or b.construction.complete) then
			local dx = b.tileX - firstBuilder.tileX
			local dy = b.tileY - firstBuilder.tileY
			if dx*dx + dy*dy >= thresholdSq then
				if roadConnectedBetweenBuildings(state, firstBuilder, b) then return true end
			end
		end
	end
	return false
end

local function housesConnectedToMarketByRoads(state)
	local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
	local function adjRoadTiles(x, y)
		local list = {}
		for i=1,4 do
			local nx, ny = x + dirs[i][1], y + dirs[i][2]
			if hasRoad(state, nx, ny) then table.insert(list, { nx, ny }) end
		end
		return list
	end
	-- BFS from one market-adjacent road (approximation)
	local start = nil
	for _, m in ipairs(state.game.buildings or {}) do
		if m.type == 'market' then
			local adj = adjRoadTiles(m.tileX, m.tileY)
			if #adj > 0 then start = adj[1]; break end
		end
	end
	if not start then return 0, 0 end
	local K = function(x,y) return x .. "," .. y end
	local q = { start }
	local head = 1
	local visited = { [K(start[1], start[2])] = true }
	while q[head] do
		local cx, cy = q[head][1], q[head][2]
		head = head + 1
		for i=1,4 do
			local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
			if hasRoad(state, nx, ny) and not visited[K(nx,ny)] then
				visited[K(nx,ny)] = true
				table.insert(q, { nx, ny })
			end
		end
	end
	local covered, total = 0, 0
	for _, h in ipairs(state.game.buildings or {}) do
		if h.type == 'house' and (not h.construction or h.construction.complete) then
			total = total + 1
			local adj = adjRoadTiles(h.tileX, h.tileY)
			for _, a in ipairs(adj) do if visited[K(a[1], a[2])] then covered = covered + 1; break end end
		end
	end
	return covered, total
end

-- Food helpers
local function computeTotalMarketFood(state)
	local total = 0
	for _, b in ipairs(state.game.buildings or {}) do
		if b.type == 'market' and b.storage and b.storage.food then
			total = total + b.storage.food
		end
	end
	return total
end

local function housesCoveredByAnyMarket(state)
	local covered, total = 0, 0
	local radius = (state.buildingDefs.market and state.buildingDefs.market.radiusTiles) or 0
	for _, h in ipairs(state.game.buildings or {}) do
		if h.type == 'house' and (not h.construction or h.construction.complete) then
			total = total + 1
			local ok = false
			for _, m in ipairs(state.game.buildings or {}) do
				if m.type == 'market' then
					local dx = m.tileX - h.tileX
					local dy = m.tileY - h.tileY
					if dx*dx + dy*dy <= radius*radius then ok = true; break end
				end
			end
			if ok then covered = covered + 1 end
		end
	end
	return covered, total
end

local function allObjectivesComplete(objs)
	for _, o in ipairs(objs) do if not o.done then return false end end
	return true
end

-- Roads helpers: detect any road loop and approximate its length
local function computeAnyRoadLoopLength(state)
    local roadsMap = state.game and state.game.roads or {}
    if not roadsMap then return 0 end
    local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
    local function K(x,y) return x .. "," .. y end
    local function has(x,y)
        return roadsMap[K(x,y)] ~= nil
    end
    local globalVisited = {}
    for _, rd in pairs(roadsMap) do
        local sx, sy = rd.tileX, rd.tileY
        local sk = K(sx,sy)
        if not globalVisited[sk] then
            local parent = {}
            local depth = {}
            local visited = {}
            local q = { {sx, sy} }
            local head = 1
            visited[sk] = true
            depth[sk] = 0
            parent[sk] = false
            globalVisited[sk] = true
            while q[head] do
                local cx, cy = q[head][1], q[head][2]
                head = head + 1
                for i=1,4 do
                    local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
                    if has(nx, ny) then
                        local ck = K(cx,cy)
                        local nk = K(nx,ny)
                        if not visited[nk] then
                            visited[nk] = true
                            globalVisited[nk] = true
                            depth[nk] = (depth[ck] or 0) + 1
                            parent[nk] = { cx, cy }
                            q[#q+1] = { nx, ny }
                        elseif not (parent[ck] and parent[ck][1] == nx and parent[ck][2] == ny) then
                            -- Found a back/cross edge forming a cycle; estimate its length via ancestry
                            local ancestors = {}
                            local tk = ck
                            while tk do
                                ancestors[tk] = true
                                local p = parent[tk]
                                if not p then break end
                                tk = K(p[1], p[2])
                            end
                            local stepsB = 0
                            local bk = nk
                            local meet = nil
                            while bk do
                                if ancestors[bk] then meet = bk; break end
                                local p = parent[bk]
                                if not p then break end
                                bk = K(p[1], p[2])
                                stepsB = stepsB + 1
                            end
                            if meet then
                                local stepsA = 0
                                local ak = ck
                                while ak ~= meet do
                                    local p = parent[ak]
                                    if not p then break end
                                    ak = K(p[1], p[2])
                                    stepsA = stepsA + 1
                                end
                                local len = stepsA + stepsB + 1
                                if len > 0 then return len end
                            end
                        end
                    end
                end
            end
        end
    end
    return 0
end

local function setProgress(o, current, target, dt)
	o.current = math.max(0, current)
	o.target = target
	local prev = o._prev or 0
	if o.current > prev then
		o.pulse = 0.5 -- quick glow on increment
	end
	o._prev = o.current
	if o.pulse then o.pulse = math.max(0, (o.pulse or 0) - dt) end
	local wasDone = o.done
	o.done = (o.current >= (o.target or 1))
	if o.done and not wasDone then
		o.completePulse = 0.8
	end
	if o.completePulse then o.completePulse = math.max(0, o.completePulse - dt * 0.5) end
end

local function setStage1(state)
	state.mission.stage = 1
	state.mission.name = 'First Foundations'
	state.mission.description = 'Establish essential production and distribution.'
	state.mission.completed = false
	state.mission.rewardGiven = false
	state.mission.objectives = {
		{ id = 'build_lumberyard', text = 'Build 1 Lumberyard', done = false, current = 0, target = 1 },
		{ id = 'build_farm', text = 'Build 1 Farm', done = false, current = 0, target = 1 },
		{ id = 'build_market', text = 'Build 1 Market', done = false, current = 0, target = 1 }
	}
end

local function setStage2(state)
	state.mission.stage = 2
	state.mission.name = 'Food and Logistics'
	state.mission.description = 'Establish Market coverage and stock for nightly meals.'
	state.mission.completed = false
	state.mission.rewardGiven = false
	state.mission.objectives = {
		{ id = 'stock_food', text = 'Stock Markets with food equal to population', done = false, current = 0, target = 0 },
		{ id = 'build_house', text = 'Build 1 House', done = false, current = 0, target = 1 },
		{ id = 'place_roads', text = 'Lay 12 road tiles', done = false, current = 0, target = 12 }
	}
end

function missions.init(state)
	state.mission = state.mission or {}
	if state.mission.active then return end
	state.mission = { active = true }
	setStage1(state)
end

function missions.reset(state)
	state.mission = nil
	missions.init(state)
end

function missions.update(state, dt)
	if not state.mission or not state.mission.active then return end
	local M = state.mission

	-- Evaluate objectives per stage
	for _, o in ipairs(M.objectives or {}) do
		if M.stage == 1 then
			if o.id == 'build_lumberyard' then
				setProgress(o, countCompletedBuildings(state, 'lumberyard'), 1, dt)
			elseif o.id == 'build_farm' then
				setProgress(o, countCompletedBuildings(state, 'farm'), 1, dt)
			elseif o.id == 'build_market' then
				setProgress(o, countCompletedBuildings(state, 'market'), 1, dt)
			end
		elseif M.stage == 2 then
			if o.id == 'stock_food' then
				local pop = (state.game.population and state.game.population.total) or 0
				o.target = pop
				setProgress(o, computeTotalMarketFood(state), pop, dt)
			elseif o.id == 'build_house' then
				setProgress(o, countCompletedBuildings(state, 'house'), 1, dt)
			elseif o.id == 'place_roads' then
				setProgress(o, countRoadTiles(state), 12, dt)
			end
		elseif M.stage == 3 then
			if o.id == 'markets_3' then
				setProgress(o, countCompletedBuildings(state, 'market'), 3, dt)
			elseif o.id == 'feed_streak' then
				-- updated in transition below based on nightly result
				setProgress(o, M._feedStreak or 0, 2, dt)
			elseif o.id == 'roads_20' then
				setProgress(o, countRoadTiles(state), 20, dt)
			end
		elseif M.stage == 4 then
			if o.id == 'houses_4_connected' then
				setProgress(o, countHousesConnectedByRoad(state), 4, dt)
			-- finish_3 removed
			elseif o.id == 'frontier_outpost' then
				setProgress(o, (frontierOutpostAchieved(state) and 1 or 0), 1, dt)
			end
		elseif M.stage == 5 then
			if o.id == 'trees_50' then
				setProgress(o, computeLivingTrees(state), 50, dt)
			elseif o.id == 'road_loop' then
				local len = M._loopLen or 0
				setProgress(o, math.min(12, len), 12, dt)
			elseif o.id == 'logistics_day' then
				local pct = 100 - (M._logisticsPct or 0)
				pct = math.max(0, math.min(100, pct))
				-- Represent progress as time satisfied; UI will also show current %
				local elapsed = (M._logisticsTimer or 0)
				local target = (state.time and state.time.dayLength) or 60
				setProgress(o, math.min(target, elapsed), target, dt)
			end
		elseif M.stage == 6 then
			if o.id == 'stock_150' then
				local pop = (state.game.population and state.game.population.total) or 0
				local target = math.floor(pop * 1.5 + 0.5)
				setProgress(o, computeTotalMarketFood(state), target, dt)
			elseif o.id == 'night_ok' then
				setProgress(o, (M._nightOk and 1 or 0), 1, dt)
			elseif o.id == 'houses_connected' then
				local covered, total = housesConnectedToMarketByRoads(state)
				local pct = (total > 0) and math.floor((covered / total) * 100 + 0.5) or 0
				setProgress(o, pct, 100, dt)
			end
		elseif M.stage == 7 then
			if o.id == 'top_finish' then
				setProgress(o, (M._topFinishOk and 1 or 0), 1, dt)
			elseif o.id == 'no_idle_day' then
				setProgress(o, (M._noIdleOk and 1 or 0), 1, dt)
			end
		end
	end

	-- Stage completion handling
	if not M.completed and allObjectivesComplete(M.objectives) then
		M.completed = true
		-- notify (persist for 10 real seconds)
		state.ui.promptText = 'Mission Complete: ' .. (M.name or '') .. '!'
		state.ui.promptT = 0
		state.ui.promptDuration = 10
		state.ui._promptUseRealTime = true
		state.ui.promptSticky = false
		-- small reward on stage 1
		if M.stage == 1 and not M.rewardGiven then
			state.game.resources.wood = (state.game.resources.wood or 0) + 20
			M.rewardGiven = true
		end
		M.advanceTimer = 0 -- switch stages immediately to avoid stalls; prompt already shows
		-- Confetti from all villagers
		if state.game and state.game.villagers then
			local TILE = require('src.constants').TILE_SIZE
			local particles = require('src.particles')
			for _, v in ipairs(state.game.villagers) do
				particles.spawnConfetti(state.game.particles, v.x, v.y)
			end
			-- also from homes as a burst
			for _, b in ipairs(state.game.buildings or {}) do
				if b.type == 'house' and (not b.construction or b.construction.complete) then
					local px = b.tileX * TILE + TILE / 2
					local py = b.tileY * TILE + TILE / 2
					particles.spawnConfetti(state.game.particles, px, py)
				end
			end
		end
		-- Immediately advance to next stage
		local prev = M.stage
		if prev == 1 then
			setStage2(state)
		elseif prev == 2 then
			state.mission.stage = 3
			state.mission.name = 'Night Market City'
			state.mission.description = 'Feed nights and expand the market network.'
			state.mission.completed = false
			state.mission.rewardGiven = false
			state.mission.objectives = {
				{ id = 'markets_3', text = 'Build 2 additional Markets (total 3)', done = false, current = 0, target = 3 },
				{ id = 'feed_streak', text = 'Feed everyone for 2 consecutive nights', done = false, current = 0, target = 2 },
				{ id = 'roads_20', text = 'Lay 20 road tiles', done = false, current = 0, target = 20 }
			}
			state.mission._feedStreak = 0
		elseif prev == 3 then
			state.mission.stage = 4
			state.mission.name = "Builders' Pride"
			state.mission.description = 'Grow housing and execute plans with discipline.'
			state.mission.completed = false
			state.mission.rewardGiven = false
			local completedNow = 0
			for _, b in ipairs(state.game.buildings or {}) do if b.construction and b.construction.complete then completedNow = completedNow + 1 end end
			state.mission._completedBaseline = completedNow
			state.mission._buildersTimer = 0
			state.mission.objectives = {
				{ id = 'houses_4_connected', text = 'Block Party: Build 4 Houses, each connected to the road network', done = false, current = 0, target = 4 },
				{ id = 'frontier_outpost', text = "Frontier Outpost: Builder’s Workplace ≥ 50 tiles from the first, road-connected", done = false, current = 0, target = 1 }
			}
		elseif prev == 4 then
			state.mission.stage = 5
			state.mission.name = 'Green Belt'
			state.mission.description = 'Balance nature and infrastructure.'
			state.mission.completed = false
			state.mission.rewardGiven = false
			state.mission.objectives = {
				{ id = 'trees_50', text = 'Have 50 living trees in the city', done = false, current = 0, target = 50 },
				{ id = 'road_loop', text = 'Create a road loop of at least 12 tiles', done = false, current = 0, target = 1 },
				{ id = 'logistics_day', text = 'Keep storage below 90% full for a day', done = false, current = 0, target = 1 }
			}
			state.mission._logisticsTimer = 0
		elseif prev == 5 then
			state.mission.stage = 6
			state.mission.name = 'Festival Day'
			state.mission.description = 'Prepare supplies and roads for the crowd.'
			state.mission.completed = false
			state.mission.rewardGiven = false
			state.mission.objectives = {
				{ id = 'stock_150', text = 'Stock Markets with 1.5x population food before dusk', done = false, current = 0, target = 150 },
				{ id = 'night_ok', text = 'Survive one night with zero starvation', done = false, current = 0, target = 1 },
				{ id = 'houses_connected', text = 'Connect every House to a Market via roads', done = false, current = 0, target = 100 }
			}
		elseif prev == 6 then
			state.mission.stage = 7
			state.mission.name = 'Master Planner'
			state.mission.description = 'Execute flawlessly and keep everyone busy.'
			state.mission.completed = false
			state.mission.rewardGiven = false
			state.mission.objectives = {
				{ id = 'top_finish', text = 'Complete a building while never pausing during the day', done = false, current = 0, target = 1 },
				{ id = 'no_idle_day', text = 'Zero idle warnings on worker buildings for a day', done = false, current = 0, target = 1 }
			}
			state.mission._noIdleTimer = 0
		end
		state.ui.promptText = 'New Objectives: ' .. (state.mission.name or '')
		state.ui.promptT = 0
		state.ui.promptDuration = 3.5
		state.ui._promptUseRealTime = true
		state.ui.promptSticky = false
	end

	-- Advance to next stage after timer
	if M.completed and M.advanceTimer then
		M.advanceTimer = M.advanceTimer - dt
		if M.advanceTimer <= 0 and not M._advanced then
			M._advanced = true
			if M.stage == 1 then
				setStage2(state)
			elseif M.stage == 2 then
				-- Stage 3 – Night Market City
				state.mission.stage = 3
				state.mission.name = 'Night Market City'
				state.mission.description = 'Feed nights and expand the market network.'
				state.mission.completed = false
				state.mission.rewardGiven = false
				state.mission.objectives = {
					{ id = 'markets_3', text = 'Build 2 additional Markets (total 3)', done = false, current = 0, target = 3 },
					{ id = 'feed_streak', text = 'Feed everyone for 2 consecutive nights', done = false, current = 0, target = 2 },
					{ id = 'roads_20', text = 'Lay 20 road tiles', done = false, current = 0, target = 20 }
				}
				state.mission._feedStreak = 0
			elseif M.stage == 3 then
				-- Stage 4 – Builders’ Pride
				state.mission.stage = 4
				state.mission.name = "Builders' Pride"
				state.mission.description = 'Grow housing and execute plans with discipline.'
				state.mission.completed = false
				state.mission.rewardGiven = false
				local completedNow = 0
				for _, b in ipairs(state.game.buildings or {}) do if b.construction and b.construction.complete then completedNow = completedNow + 1 end end
				state.mission._completedBaseline = completedNow
				state.mission._buildersTimer = 0
				state.mission.objectives = {
					{ id = 'houses_4_connected', text = 'Block Party: Build 4 Houses, each connected to the road network', done = false, current = 0, target = 4 },
					{ id = 'frontier_outpost', text = "Frontier Outpost: Builder’s Workplace ≥ 50 tiles from the first, road-connected", done = false, current = 0, target = 1 }
				}
			elseif M.stage == 4 then
				-- Stage 5 – Green Belt
				state.mission.stage = 5
				state.mission.name = 'Green Belt'
				state.mission.description = 'Balance nature and infrastructure.'
				state.mission.completed = false
				state.mission.rewardGiven = false
				state.mission.objectives = {
					{ id = 'trees_50', text = 'Have 50 living trees in the city', done = false, current = 0, target = 50 },
					{ id = 'road_loop', text = 'Create a road loop of at least 12 tiles', done = false, current = 0, target = 1 },
					{ id = 'logistics_day', text = 'Keep storage below 90% full for a day', done = false, current = 0, target = 1 }
				}
				state.mission._logisticsTimer = 0
			elseif M.stage == 5 then
				-- Stage 6 – Festival Day
				state.mission.stage = 6
				state.mission.name = 'Festival Day'
				state.mission.description = 'Prepare supplies and roads for the crowd.'
				state.mission.completed = false
				state.mission.rewardGiven = false
				state.mission.objectives = {
					{ id = 'stock_150', text = 'Stock Markets with 1.5x population food before dusk', done = false, current = 0, target = 150 },
					{ id = 'night_ok', text = 'Survive one night with zero starvation', done = false, current = 0, target = 1 },
					{ id = 'houses_connected', text = 'Connect every House to a Market via roads', done = false, current = 0, target = 100 }
				}
			elseif M.stage == 6 then
				-- Stage 7 – Master Planner
				state.mission.stage = 7
				state.mission.name = 'Master Planner'
				state.mission.description = 'Execute flawlessly and keep everyone busy.'
				state.mission.completed = false
				state.mission.rewardGiven = false
				state.mission.objectives = {
					{ id = 'top_finish', text = 'Complete a building while never pausing during the day', done = false, current = 0, target = 1 },
					{ id = 'no_idle_day', text = 'Zero idle warnings on worker buildings for a day', done = false, current = 0, target = 1 }
				}
				state.mission._noIdleTimer = 0
			end
			state.ui.promptText = 'New Objectives: ' .. (state.mission.name or '')
			state.ui.promptT = 0
			state.ui.promptDuration = 3.5
			state.ui._promptUseRealTime = true
			state.ui.promptSticky = false
		end
	end

  -- Cross-stage trackers updated continuously
  -- Stage 3: feed streak increments exactly once per night when mealtime resolves
  if M.stage == 3 and state.time then
    -- Reset the per-night gate after sunrise (mealtime flag is cleared at sunrise in main)
    if not state.time.mealConsumedToday then
      M._countedThisNight = false
    end
    if state.time.mealConsumedToday and state.time.lastMealOk ~= nil and not M._countedThisNight then
      if state.time.lastMealOk then
        M._feedStreak = math.min(999, (M._feedStreak or 0) + 1)
      else
        M._feedStreak = 0
      end
      M._countedThisNight = true
    end
  end
  -- Stage 4: frontier outpost has no time-based tracker; handled in evaluation
  -- Stage 5: road loop and logistics discipline
  if M.stage == 5 then
    -- loop detection (cheap check occasionally)
    if (love.timer.getTime() % 1.0) < dt then
      local loopLen = computeAnyRoadLoopLength(state)
      M._loopLen = loopLen
      M._hasLoop = loopLen >= 12
    end
    -- storage under 90% for a full day clock
    local woodTotal = (state.game.resources.wood or 0)
    for _, b in ipairs(state.game.buildings or {}) do
      if b.type == 'warehouse' and b.storage and b.storage.wood then woodTotal = woodTotal + b.storage.wood end
    end
    local cap = computeWoodCapacity(state)
    -- Show current state to the player
    M._logisticsPct = cap > 0 and math.floor((woodTotal / cap) * 100 + 0.5) or 0
    if woodTotal <= cap * 0.9 then
      M._logisticsTimer = (M._logisticsTimer or 0) + dt
      if M._logisticsTimer >= state.time.dayLength then M._logisticsOk = true end
    else
      M._logisticsTimer = 0
    end
  end
  -- Stage 6: nightly ok tracked by main via lastMealOk; here just mirror quickly post-meal
  if M.stage == 6 and state.time and state.time.mealConsumedToday and state.time.lastMealOk ~= nil then
    M._nightOk = state.time.lastMealOk
  end
  -- Stage 7: example flags could be set elsewhere; leave as manual for now
end

return missions 