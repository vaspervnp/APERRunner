-- =============================================================================
-- Sheet "bridges": 144x8 rows spanning the whole playfield
-- (side 30 | 3 lanes x 28 | side 30). Index 0 = row nearest the player.
-- The player passes under them. Shadow rows darken what lies below with a
-- dither of black/blue over a generic track + verge pattern.
-- =============================================================================

dofile(GFX .. "src\\common.lua")

local W, H = 144, 8
local LANES = { 30, 58, 86 }             -- lane x starts
local RAILS = { 6, 20 }

-- what lies under a bridge shadow: verges, ballast and rails, darkened
local function shadow_row(seed)
  local c = Canvas(W, H)
  for y = 0, H - 1 do for x = 0, W - 1 do
    c:px(x, y, ((x + y) % 2 == 0) and BLACK or BLUE)
  end end
  for _, lx in ipairs(LANES) do
    for _, rx in ipairs(RAILS) do c:vline(lx + rx, 0, H - 1, GREY) end
    for y = 1, H - 1, 4 do
      for x = lx + 3, lx + 24, 2 do c:px(x, y, RED) end
    end
  end
  return c
end

-- --- footbridge: steel truss deck, 3 rows ----------------------------------------
local function footbridge(index)
  local c = Canvas(W, H)
  -- deck: tiles in red/olive with joints
  for y = 0, H - 1 do for x = 0, W - 1 do
    c:px(x, y, ((x // 4 + y // 4) % 2 == 0) and RED or OLIVE)
  end end
  for x = 0, W - 1, 8 do c:vline(x, 0, H - 1, BLACK) end
  if index == 0 then                         -- railing on the near edge
    c:hline(0, W - 1, 5, WHITE)
    c:hline(0, W - 1, 6, GREY)
    c:hline(0, W - 1, 7, BLACK)
    for x = 0, W - 1, 6 do c:rect(x, 4, x + 1, 6, WHITE) end
  elseif index == 2 then                     -- railing on the far edge
    c:hline(0, W - 1, 0, BLACK)
    c:hline(0, W - 1, 1, WHITE)
    c:hline(0, W - 1, 2, GREY)
    for x = 0, W - 1, 6 do c:rect(x, 1, x + 1, 3, WHITE) end
  else                                       -- middle: a couple of pedestrians
    for _, px in ipairs({ 40, 96 }) do
      c:rect(px, 2, px + 1, 5, BRED)
      c:rect(px, 1, px + 1, 1, PINK)
    end
    c:rect(70, 3, 71, 6, BBLUE); c:rect(70, 2, 71, 2, PINK)
  end
  return c
end

-- --- road bridge: 6 rows ------------------------------------------------------------
local function road_bridge(index)
  local c = Canvas(W, H)
  for y = 0, H - 1 do for x = 0, W - 1 do
    c:px(x, y, (noise(x // 2, y, 300 + index) < 0.05) and BLACK or GREY)
  end end
  if index == 0 or index == 5 then           -- concrete parapet + sidewalk
    local parapet = (index == 0) and { 6, 7 } or { 0, 1 }
    local walk = (index == 0) and { 0, 5 } or { 2, 7 }
    c:rect(0, walk[1], W - 1, walk[2], GREY)
    for x = 0, W - 1, 6 do c:vline(x, walk[1], walk[2], WHITE) end
    c:rect(0, parapet[1], W - 1, parapet[2], WHITE)
    c:hline(0, W - 1, (index == 0) and 7 or 0, BLACK)
  elseif index == 1 or index == 4 then       -- kerb + outer lane
    c:hline(0, W - 1, (index == 1) and 7 or 0, WHITE)
  elseif index == 2 then                     -- centre line (double)
    c:hline(0, W - 1, 7, WHITE)
  elseif index == 3 then
    c:hline(0, W - 1, 0, WHITE)
  end
  -- traffic crossing the bridge (side views from above: 16x6 cars)
  local function car(x, y, body)
    c:rect(x, y, x + 15, y + 4, body)
    c:hline(x, x + 15, y + 5, BLACK)
    c:rect(x + 4, y + 1, x + 6, y + 3, SKY)
    c:rect(x + 10, y + 1, x + 11, y + 3, BLUE)
  end
  if index == 1 then car(20, 1, BRED); car(104, 1, YELLOW) end
  if index == 4 then car(60, 1, BBLUE) end
  return c
end

local frames = {}
for i = 0, 2 do frames[#frames + 1] = { name = "footbridge_" .. i, canvas = footbridge(i) } end
frames[#frames + 1] = { name = "footbridge_shadow", canvas = shadow_row(1) }
for i = 0, 5 do frames[#frames + 1] = { name = "roadbridge_" .. i, canvas = road_bridge(i) } end
frames[#frames + 1] = { name = "roadbridge_shadow", canvas = shadow_row(2) }
build_sheet("bridges", frames)
