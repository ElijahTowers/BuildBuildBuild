-- bushes.lua
-- Berry bush generation, rendering, and gentle wind sway

local constants = require('src.constants')
local colors = constants.colors
local trees = require('src.trees')

local bushes = {}

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

local function mulColor(c, m)
	return { clamp01(c[1] * m), clamp01(c[2] * m), clamp01(c[3] * m), c[4] or 1 }
end

local function getWindOffset(b)
	local t = (b.windTime or 0) + (b.windPhase or 0)
	local sway = 0.03 + 0.02 * math.sin(t * 0.33)
	local ox = math.sin(t * 0.7) * sway
	local oy = math.cos(t * 0.6) * sway
	return ox, oy
end

function bushes.generate(state)
	local TILE_SIZE = constants.TILE_SIZE
	local world = state.world
	local list = {}

	local tilesX = world.tilesX
	local tilesY = world.tilesY
	local clusterCount = 36
	local minClusterSize, maxClusterSize = 5, 14
	local clusterSpreadTiles = 4

	local occupied = {}
	local function key(x, y) return x .. "," .. y end

	for _ = 1, clusterCount do
		local cx = math.random(2, tilesX - 3)
		local cy = math.random(3, tilesY - 3)
		local clusterSize = math.random(minClusterSize, maxClusterSize)

		for _ = 1, clusterSize do
			local ox = math.random(-clusterSpreadTiles, clusterSpreadTiles)
			local oy = math.random(-clusterSpreadTiles, clusterSpreadTiles)
			local tx = math.max(0, math.min(tilesX - 1, cx + ox))
			local ty = math.max(0, math.min(tilesY - 1, cy + oy))
			local k = key(tx, ty)
			if not occupied[k] and not trees.getAt(state, tx, ty) then
				occupied[k] = true
				table.insert(list, {
					tileX = tx,
					tileY = ty,
					alive = true,
					sizeScale = 0.85 + math.random() * 0.3,
					colorMul = 0.9 + math.random() * 0.2,
					windPhase = math.random() * math.pi * 2,
					windTime = 0,
					berryPhase = math.random() * math.pi * 2
				})
			end
		end
	end

	state.game.bushes = list
end

function bushes.updateShake(state, dt)
	for _, b in ipairs(state.game.bushes or {}) do
		b.windTime = (b.windTime or 0) + dt
	end
end

function bushes.draw(state)
	local TILE_SIZE = constants.TILE_SIZE
	for _, b in ipairs(state.game.bushes or {}) do
		if not b.alive then goto continue end
		local cx = b.tileX * TILE_SIZE + TILE_SIZE / 2
		local cy = b.tileY * TILE_SIZE + TILE_SIZE / 2
		local r = TILE_SIZE * 0.28 * (b.sizeScale or 1)
		local ox, oy = getWindOffset(b)
		local foliageColor = mulColor(colors.bushFill or {0.16,0.5,0.22,1}, (b.colorMul or 1))

		-- shadow
		love.graphics.setColor(0, 0, 0, 0.18)
		love.graphics.ellipse('fill', cx, cy + TILE_SIZE * 0.18, r * 1.2, r * 0.5)

		-- foliage (clustered circles)
		love.graphics.setColor(foliageColor)
		love.graphics.circle('fill', cx + ox, cy + oy - r * 0.1, r)
		love.graphics.circle('fill', cx + ox - r * 0.5, cy + oy + r * 0.05, r * 0.75)
		love.graphics.circle('fill', cx + ox + r * 0.5, cy + oy + r * 0.05, r * 0.75)

		-- subtle highlights
		love.graphics.setColor(1, 1, 1, 0.07)
		love.graphics.circle('fill', cx + ox - r * 0.25, cy + oy - r * 0.4, r * 0.35)

		-- outline
		love.graphics.setColor(colors.bushOutline or {0.08,0.25,0.10,0.6})
		love.graphics.circle('line', cx + ox, cy + oy - r * 0.1, r)

		-- berries (sprinkled)
		local berryColor = colors.berry or {0.85, 0.2, 0.2, 1}
		love.graphics.setColor(berryColor)
		local n = 5 + math.floor((b.sizeScale or 1) * 3)
		for i = 1, n do
			local a = b.berryPhase + i * (math.pi * 2 / n)
			local rr = r * (0.25 + 0.4 * ((i % 2 == 0) and 1 or 0.7))
			local bx = cx + ox + math.cos(a) * rr
			local by = cy + oy + math.sin(a) * rr * 0.8
			love.graphics.circle('fill', bx, by, math.max(1.5, r * 0.16))
		end
		-- berry shine
		love.graphics.setColor(1, 1, 1, 0.15)
		for i = 1, 3 do
			local a = b.berryPhase + i * 2.1
			local rr = r * 0.35
			local bx = cx + ox + math.cos(a) * rr
			local by = cy + oy + math.sin(a) * rr * 0.7
			love.graphics.circle('fill', bx - 1, by - 1, math.max(0.8, r * 0.08))
		end

		::continue::
	end
end

function bushes.removeAt(state, tileX, tileY)
	for _, b in ipairs(state.game.bushes or {}) do
		if b.alive and b.tileX == tileX and b.tileY == tileY then
			b.alive = false
			return true
		end
	end
	return false
end

return bushes 