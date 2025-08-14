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

function missions.init(state)
	state.mission = state.mission or {}
	if state.mission.active then return end
	state.mission = {
		active = true,
		name = 'Getting Started',
		description = 'Set up wood production and fill your initial storage.',
		completed = false,
		rewardGiven = false,
		objectives = {
			{ id = 'build_lumberyard', text = 'Build 1 Lumberyard (construction complete)', done = false, current = 0, target = 1 },
			{ id = 'assign_workers', text = 'Assign 2 workers to Lumberyards', done = false, current = 0, target = 2 },
			{ id = 'store_100', text = 'Reach 100 total wood in storage', done = false, current = 0, target = 100 }
		}
	}
end

function missions.reset(state)
	state.mission = nil
	missions.init(state)
end

function missions.update(state, dt)
	if not state.mission or not state.mission.active or state.mission.completed then return end
	local M = state.mission
	-- Evaluate objectives fancily with progress and pulses
	for _, o in ipairs(M.objectives) do
		if o.id == 'build_lumberyard' then
			setProgress(o, countCompletedBuildings(state, 'lumberyard'), 1, dt)
		elseif o.id == 'assign_workers' then
			setProgress(o, sumAssignedLumberyardWorkers(state), 2, dt)
		elseif o.id == 'store_100' then
			setProgress(o, computeTotalWood(state), 100, dt)
		end
	end
	-- Completion
	if allObjectivesComplete(M.objectives) then
		M.completed = true
		if not M.rewardGiven then
			state.game.resources.wood = (state.game.resources.wood or 0) + 20
			M.rewardGiven = true
			state.ui.promptText = 'Mission Complete: Getting Started! (+20 wood)'
			state.ui.promptT = 0
			state.ui.promptDuration = 4
			state.ui.promptSticky = false
		end
	end
end

return missions 