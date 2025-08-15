-- save.lua
-- Save/load game state to JSON using Love2D filesystem

local json = require('src.json')

local save = {}

local function cloneShallow(tbl)
	local t = {}
	for k, v in pairs(tbl) do t[k] = v end
	return t
end

local function serializeState(state)
	-- Only store deterministic game data
	local S = {}
	-- World
	S.world = { tilesX = state.world.tilesX, tilesY = state.world.tilesY }
	-- Time
	S.time = { t = state.time.t, dayLength = state.time.dayLength, speed = state.time.speed }
	-- Resources
	S.game = {}
	S.game.resources = { wood = state.game.resources.wood or 0 }
	-- Trees (alive only)
	S.game.trees = {}
	for _, t in ipairs(state.game.trees or {}) do
		S.game.trees[#S.game.trees + 1] = { tileX = t.tileX, tileY = t.tileY, alive = t.alive ~= false }
	end
	-- Bushes (alive only)
	S.game.bushes = {}
	for _, b in ipairs(state.game.bushes or {}) do
		S.game.bushes[#S.game.bushes + 1] = { tileX = b.tileX, tileY = b.tileY, alive = b.alive ~= false }
	end
	-- Buildings
	S.game.buildings = {}
	for _, b in ipairs(state.game.buildings or {}) do
		local sb = {
			type = b.type,
			tileX = b.tileX,
			tileY = b.tileY,
			assigned = b.assigned or 0,
			storage = b.storage or {},
			construction = b.construction and { required = b.construction.required, progress = b.construction.progress, complete = b.construction.complete } or nil
		}
		S.game.buildings[#S.game.buildings + 1] = sb
	end
	-- Roads
	S.game.roads = {}
	for k, rd in pairs(state.game.roads or {}) do
		S.game.roads[#S.game.roads + 1] = { tileX = rd.tileX, tileY = rd.tileY }
	end
	-- Population
	S.game.population = cloneShallow(state.game.population or {})
	return S
end

local function deserializeInto(state, S)
	-- Reset structures
	state.game.trees = {}
	state.game.buildings = {}
	state.game.roads = {}
	state.game.villagers = {}
	state.game.particles = {}

	-- World/time
	state.world.tilesX = S.world.tilesX
	state.world.tilesY = S.world.tilesY
	state.time.t = S.time.t or 0
	state.time.dayLength = S.time.dayLength or state.time.dayLength
	state.time.speed = S.time.speed or 1
	state.time.normalized = state.time.t / state.time.dayLength

	-- Resources
	state.game.resources.wood = (S.game.resources and S.game.resources.wood) or 0

	-- Trees
	for _, t in ipairs(S.game.trees or {}) do
		state.game.trees[#state.game.trees + 1] = {
			tileX = t.tileX, tileY = t.tileY,
			alive = t.alive ~= false,
			reserved = false,
			beingChopped = false,
			health = 10
		}
	end
	-- Bushes
	state.game.bushes = {}
	for _, b in ipairs(S.game.bushes or {}) do
		state.game.bushes[#state.game.bushes + 1] = {
			tileX = b.tileX, tileY = b.tileY,
			alive = b.alive ~= false,
			windTime = 0,
			windPhase = math.random() * math.pi * 2,
			colorMul = 1,
			sizeScale = 1
		}
	end
	-- Ensure no overlap: if a tile has both a tree and a bush, keep the tree and remove the bush
	if state.game.trees and state.game.bushes then
		local hasTree = {}
		for _, t in ipairs(state.game.trees) do
			if t.alive then hasTree[string.format('%d,%d', t.tileX, t.tileY)] = true end
		end
		for _, b in ipairs(state.game.bushes) do
			if b.alive and hasTree[string.format('%d,%d', b.tileX, b.tileY)] then
				b.alive = false
			end
		end
	end
	-- Buildings
	for _, sb in ipairs(S.game.buildings or {}) do
		local color
		if sb.type == 'house' then color = { 0.9, 0.6, 0.2, 1.0 }
		elseif sb.type == 'lumberyard' then color = { 0.3, 0.7, 0.3, 1.0 }
		elseif sb.type == 'warehouse' then color = { 0.6, 0.6, 0.7, 1.0 }
		elseif sb.type == 'builder' then color = { 0.7, 0.5, 0.3, 1.0 }
		else color = { 0.8, 0.8, 0.8, 1.0 } end
		local b = {
			type = sb.type,
			tileX = sb.tileX, tileY = sb.tileY,
			assigned = sb.assigned or 0,
			storage = sb.storage or {},
			anim = { appear = 1, t = 0, active = false },
			color = color,
			construction = sb.construction or nil
		}
		state.game.buildings[#state.game.buildings + 1] = b
	end
	-- Roads
	state.game.roads = state.game.roads or {}
	for _, rd in ipairs(S.game.roads or {}) do
		state.game.roads[string.format('%d,%d', rd.tileX, rd.tileY)] = { tileX = rd.tileX, tileY = rd.tileY }
	end
	-- Population
	state.game.population = S.game.population or { total = 0, assigned = 0, capacity = 0 }
end

function save.saveToSlot(state, slot)
	local payload = serializeState(state)
	local s = json.encode(payload)
	local filename = string.format('save_%d.json', slot or 1)
	love.filesystem.write(filename, s)
	return true, filename
end

function save.loadFromSlot(state, slot)
	local filename = string.format('save_%d.json', slot or 1)
	if not love.filesystem.getInfo(filename) then return false, 'No save in slot ' .. tostring(slot or 1) end
	local s = love.filesystem.read(filename)
	local tbl, err = json.decode(s)
	if not tbl then return false, err end
	deserializeInto(state, tbl)
	return true
end

return save 