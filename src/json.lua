-- json.lua
-- Minimal JSON encoder/decoder (sufficient for game state serialization)
-- Supports: tables (arrays/objects), numbers, booleans, strings, nil (encoded as null)

local json = {}

local function escapeStr(s)
	return s:gsub('\\', '\\\\')
			 :gsub('"', '\\"')
			 :gsub('\n', '\\n')
			 :gsub('\r', '\\r')
			 :gsub('\t', '\\t')
end

local function isArray(t)
	local n = 0
	for k, _ in pairs(t) do
		if type(k) ~= 'number' then return false end
		n = math.max(n, k)
	end
	for i = 1, n do
		if t[i] == nil then return false end
	end
	return true
end

local function encodeValue(v)
	local tv = type(v)
	if tv == 'string' then
		return '"' .. escapeStr(v) .. '"'
	elseif tv == 'number' or tv == 'boolean' then
		return tostring(v)
	elseif tv == 'nil' then
		return 'null'
	elseif tv == 'table' then
		if isArray(v) then
			local parts = {}
			for i = 1, #v do parts[#parts + 1] = encodeValue(v[i]) end
			return '[' .. table.concat(parts, ',') .. ']'
		else
			local parts = {}
			for k, val in pairs(v) do
				if type(k) ~= 'string' then k = tostring(k) end
				parts[#parts + 1] = '"' .. escapeStr(k) .. '":' .. encodeValue(val)
			end
			return '{' .. table.concat(parts, ',') .. '}'
		end
	end
	error('Unsupported type in JSON encode: ' .. tv)
end

function json.encode(tbl)
	return encodeValue(tbl)
end

-- Decoder (simple recursive descent)
local function createCtx(s)
	return { s = s, i = 1, n = #s }
end

local function skipWS(ctx)
	local i, n, s = ctx.i, ctx.n, ctx.s
	while i <= n do
		local c = s:sub(i, i)
		if c == ' ' or c == '\n' or c == '\r' or c == '\t' then i = i + 1 else break end
	end
	ctx.i = i
end

local function parseLiteral(ctx, lit, val)
	if ctx.s:sub(ctx.i, ctx.i + #lit - 1) == lit then
		ctx.i = ctx.i + #lit
		return val
	end
	error('Invalid JSON near position ' .. ctx.i)
end

local function parseString(ctx)
	local s, i, n = ctx.s, ctx.i + 1, ctx.n -- skip opening quote
	local out = {}
	while i <= n do
		local c = s:sub(i, i)
		if c == '"' then ctx.i = i + 1; return table.concat(out) end
		if c == '\\' then
			local nxt = s:sub(i + 1, i + 1)
			if nxt == '"' or nxt == '\\' or nxt == '/' then out[#out + 1] = nxt; i = i + 2
			elseif nxt == 'b' then out[#out + 1] = '\b'; i = i + 2
			elseif nxt == 'f' then out[#out + 1] = '\f'; i = i + 2
			elseif nxt == 'n' then out[#out + 1] = '\n'; i = i + 2
			elseif nxt == 'r' then out[#out + 1] = '\r'; i = i + 2
			elseif nxt == 't' then out[#out + 1] = '\t'; i = i + 2
			elseif nxt == 'u' then
				-- rudimentary unicode escape handling: skip 4 hex digits
				local hex = s:sub(i + 2, i + 5)
				out[#out + 1] = '?' -- placeholder
				i = i + 6
			else
				error('Invalid escape at pos ' .. i)
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	error('Unclosed string')
end

local function parseNumber(ctx)
	local s, i, n = ctx.s, ctx.i, ctx.n
	local j = i
	while j <= n and s:sub(j, j):match('[0-9%+%-%eE%.]') do j = j + 1 end
	local numStr = s:sub(i, j - 1)
	ctx.i = j
	return tonumber(numStr)
end

local function parseArray(ctx)
	ctx.i = ctx.i + 1 -- skip [
	skipWS(ctx)
	local arr = {}
	if ctx.s:sub(ctx.i, ctx.i) == ']' then ctx.i = ctx.i + 1; return arr end
	while true do
		arr[#arr + 1] = json._parse(ctx)
		skipWS(ctx)
		local c = ctx.s:sub(ctx.i, ctx.i)
		if c == ',' then ctx.i = ctx.i + 1; skipWS(ctx)
		elseif c == ']' then ctx.i = ctx.i + 1; return arr
		else error('Expected , or ] at pos ' .. ctx.i) end
	end
end

local function parseObject(ctx)
	ctx.i = ctx.i + 1 -- skip {
	skipWS(ctx)
	local obj = {}
	if ctx.s:sub(ctx.i, ctx.i) == '}' then ctx.i = ctx.i + 1; return obj end
	while true do
		if ctx.s:sub(ctx.i, ctx.i) ~= '"' then error('Expected string key at pos ' .. ctx.i) end
		local key = parseString(ctx)
		skipWS(ctx)
		if ctx.s:sub(ctx.i, ctx.i) ~= ':' then error('Expected : at pos ' .. ctx.i) end
		ctx.i = ctx.i + 1
		skipWS(ctx)
		obj[key] = json._parse(ctx)
		skipWS(ctx)
		local c = ctx.s:sub(ctx.i, ctx.i)
		if c == ',' then ctx.i = ctx.i + 1; skipWS(ctx)
		elseif c == '}' then ctx.i = ctx.i + 1; return obj
		else error('Expected , or } at pos ' .. ctx.i) end
	end
end

function json._parse(ctx)
	skipWS(ctx)
	local c = ctx.s:sub(ctx.i, ctx.i)
	if c == '"' then return parseString(ctx)
	elseif c == '{' then return parseObject(ctx)
	elseif c == '[' then return parseArray(ctx)
	elseif c == '-' or c:match('%d') then return parseNumber(ctx)
	elseif c == 't' then return parseLiteral(ctx, 'true', true)
	elseif c == 'f' then return parseLiteral(ctx, 'false', false)
	elseif c == 'n' then return parseLiteral(ctx, 'null', nil)
	else error('Unexpected character at pos ' .. ctx.i .. ': ' .. tostring(c)) end
end

function json.decode(s)
	local ctx = createCtx(s)
	local ok, result = pcall(json._parse, ctx)
	if not ok then return nil, result end
	return result
end

return json 