-- constants.lua
-- Centralized visual and sizing constants used by multiple modules

local constants = {}

constants.TILE_SIZE = 32

constants.colors = {
  background = { 0.12, 0.12, 0.14, 1.0 },
  grid = { 0.22, 0.22, 0.25, 1.0 },
  uiPanel = { 0.15, 0.15, 0.18, 1.0 },
  uiPanelOutline = { 1, 1, 1, 0.08 },
  button = { 0.20, 0.20, 0.24, 1.0 },
  buttonHover = { 0.26, 0.26, 0.30, 1.0 },
  text = { 0.92, 0.92, 0.95, 1.0 },
  preview = { 1.0, 1.0, 1.0, 0.35 },
  invalid = { 0.9, 0.2, 0.2, 0.35 },
  outline = { 1.0, 1.0, 1.0, 0.3 },
  treeFill = { 0.15, 0.55, 0.20, 1.0 },
  treeOutline = { 0.08, 0.25, 0.10, 0.7 },
  radius = { 0.3, 0.7, 0.3, 0.12 },
  radiusOutline = { 0.35, 0.8, 0.35, 0.25 },
  particleLeaf = { 0.35, 0.75, 0.35, 0.9 },
  worker = { 0.95, 0.88, 0.6, 1.0 },
  workerCarry = { 0.55, 0.35, 0.2, 1.0 },
  choppingRing = { 1.0, 1.0, 1.0, 0.3 }
}

return constants 