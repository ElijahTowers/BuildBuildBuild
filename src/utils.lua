-- utils.lua
-- Small utility helpers used across modules

local utils = {}

function utils.isPointInRect(px, py, rx, ry, rw, rh)
  return px >= rx and px <= (rx + rw) and py >= ry and py <= (ry + rh)
end

function utils.distance(ax, ay, bx, by)
  local dx = ax - bx
  local dy = ay - by
  return math.sqrt(dx * dx + dy * dy)
end

function utils.distanceSq(ax, ay, bx, by)
  local dx = ax - bx
  local dy = ay - by
  return dx * dx + dy * dy
end

function utils.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

return utils 