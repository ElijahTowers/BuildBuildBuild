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

local function allObjectivesComplete(objs)
	for _, o in ipairs(objs) do if not o.done then return false end end
	return true
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
	state.mission.name = 'Getting Started'
	state.mission.description = 'Set up wood production and fill your initial storage.'
	state.mission.completed = false
	state.mission.rewardGiven = false
	state.mission.objectives = {
		{ id = 'build_lumberyard', text = 'Build 1 Lumberyard (construction complete)', done = false, current = 0, target = 1 },
		{ id = 'assign_single_2', text = 'Assign 2 workers to a single Lumberyard', done = false, current = 0, target = 2 },
		{ id = 'store_100', text = 'Reach 100 total wood in storage', done = false, current = 0, target = 100 }
	}
end

local function setStage2(state)
	state.mission.stage = 2
	state.mission.name = 'Storage and Roads'
	state.mission.description = 'Expand storage and improve logistics.'
	state.mission.completed = false
	state.mission.rewardGiven = false
	state.mission.objectives = {
		{ id = 'build_warehouse', text = 'Build 2 Warehouses (construction complete)', done = false, current = 0, target = 2 },
		{ id = 'store_200', text = 'Reach 200 total wood in storage', done = false, current = 0, target = 200 },
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
			elseif o.id == 'assign_single_2' then
				setProgress(o, maxAssignedInSingleLumberyard(state), 2, dt)
			elseif o.id == 'store_100' then
				setProgress(o, computeTotalWood(state), 100, dt)
			end
		elseif M.stage == 2 then
			if o.id == 'build_warehouse' then
				setProgress(o, countCompletedBuildings(state, 'warehouse'), 2, dt)
			elseif o.id == 'store_200' then
				setProgress(o, computeTotalWood(state), 200, dt)
			elseif o.id == 'place_roads' then
				setProgress(o, countRoadTiles(state), 12, dt)
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
		M.advanceTimer = 2.5
	end

	-- Advance to next stage after timer
	if M.completed and M.advanceTimer then
		M.advanceTimer = M.advanceTimer - dt
		if M.advanceTimer <= 0 and not M._advanced then
			M._advanced = true
			if M.stage == 1 then
				setStage2(state)
				state.ui.promptText = 'New Objectives: ' .. (state.mission.name or '')
				state.ui.promptT = 0
				state.ui.promptDuration = 3.5
				state.ui._promptUseRealTime = true
				state.ui.promptSticky = false
			end
		end
	end
end

return missions 