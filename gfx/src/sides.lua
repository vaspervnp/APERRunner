-- =============================================================================
-- Sheets "urban" and "forest": 30x8 side tiles, drawn for the LEFT side
-- (x 0 = screen edge, x 29 = next to lane 1); the right side is mirrored
-- by tools/png2cpc.py.
--
-- Avenue: 3 traffic lanes of 9 px (x 0-26), kerb (27), verge (28-29).
-- =============================================================================

dofile(GFX .. "src\\common.lua")

local W, H = 30, 8

-- --- avenue ----------------------------------------------------------------------
local function asphalt(c, seed)
  for y = 0, H - 1 do for x = 0, 26 do
    -- worn asphalt: a few dark patches (2-pixel clumps), no salt-and-pepper
    local n = noise(x // 2, y, seed)
    c:px(x, y, (n < 0.05) and BLACK or GREY)
  end end
  c:vline(0, 0, H - 1, WHITE)                -- edge line
end

local function kerb(c)
  c:vline(27, 0, H - 1, WHITE)
  for y = 0, H - 1 do
    c:px(28, y, (y % 4 == 0) and OLIVE or GREEN)
    c:px(29, y, (noise(29, y, 7) < 0.3) and LIME or GREEN)
  end
end

local function dashes(c, y0, y1)
  for _, x in ipairs({ 9, 18 }) do c:vline(x, y0, y1, WHITE) end
end

local function road(seed, dash)
  local c = Canvas(W, H)
  asphalt(c, seed)
  kerb(c)
  if dash then dashes(c, 2, 5) end
  return c
end

-- zebra crossing over 2 rows: stripes along the traffic, stop line before it
local function crossing(index)
  local c = road(60 + index, false)
  for x = 2, 25, 4 do c:rect(x, 0, x + 1, H - 1, WHITE) end
  if index == 0 then c:hline(1, 26, 7, WHITE); c:hline(1, 26, 6, GREY) end
  return c
end

-- kiosk (periptero) on a sidewalk bay in the outer lane, 2 rows
local function kiosk(index)
  local c = road(70 + index, false)
  c:rect(0, 0, 9, H - 1, GREY)               -- sidewalk slabs
  for y = 0, H - 1, 4 do c:hline(0, 9, y, WHITE) end
  c:vline(10, 0, H - 1, WHITE)
  if index == 0 then                         -- front: counter and awning edge
    c:rect(1, 0, 8, 4, BRED)
    for x = 1, 8, 2 do c:px(x, 4, YELLOW) end
    c:hline(1, 8, 5, BLACK)
    c:rect(2, 1, 7, 2, YELLOW)               -- newspapers
    c:px(3, 1, WHITE); c:px(6, 2, BBLUE)
  else                                       -- roof
    c:rect(1, 2, 8, 7, BRED)
    for x = 1, 8, 2 do c:vline(x, 2, 7, YELLOW) end
    c:hline(1, 8, 1, BLACK)
    c:vline(9, 2, 7, BLACK)
  end
  return c
end

-- --- forest ------------------------------------------------------------------------
local function grass(c, seed)
  for y = 0, H - 1 do for x = 0, W - 1 do
    -- grass in clumps: light tufts and a few dark hollows on 2x2 cells
    local n = noise(x // 2, y // 2, seed)
    local pen = GREEN
    if n < 0.16 then pen = LIME elseif n < 0.22 then pen = BLACK end
    if pen == LIME and (x + y) % 2 == 1 then pen = GREEN end
    c:px(x, y, pen)
  end end
  for y = 0, H - 1 do                        -- gravel shoulder by the track
    c:px(28, y, (noise(28, y, seed) < 0.5) and OLIVE or GREY)
    c:px(29, y, OLIVE)
  end
end

local function ground(seed)
  local c = Canvas(W, H)
  grass(c, seed)
  return c
end

local function path()
  local c = ground(81)
  for y = 0, H - 1 do
    local wobble = (y % 4 < 2) and 0 or 1
    for x = 8 + wobble, 19 + wobble do
      c:px(x, y, (noise(x, y, 82) < 0.25) and RED or OLIVE)
    end
    c:px(7 + wobble, y, GREEN); c:px(20 + wobble, y, BLACK)
  end
  return c
end

local function fence()
  local c = ground(91)
  c:vline(25, 0, H - 1, RED)                 -- rail
  c:vline(26, 0, H - 1, BLACK)
  c:rect(24, 1, 26, 2, RED)                  -- post
  c:hline(24, 26, 3, BLACK)
  c:rect(24, 5, 26, 6, RED)
  c:hline(24, 26, 7, BLACK)
  return c
end

-- transitions over 2 rows (index 0 = bottom): the avenue ends at a kerb
-- and the grass begins, with a ragged edge.
local function transition(from_urban, index)
  local urban = road(100 + index, false)
  local forest = ground(110 + index)
  local c = Canvas(W, H)
  for x = 0, W - 1 do
    -- boundary line, 0..15 from the bottom of row 0; ragged by +-1
    local edge = 8 + math.floor(noise(x // 2, 0, 120) * 3) - 1
    for y = 0, H - 1 do
      local from_bottom = (1 - index) * 0 + index * 8 + (7 - y)
      local beyond = from_bottom >= edge            -- above the edge
      local take_forest = (beyond == from_urban)
      local pen = take_forest and forest:get(x, y) or urban:get(x, y)
      if from_bottom == edge - (from_urban and 1 or 0) and x <= 27 then pen = WHITE end   -- kerb
      c:px(x, y, pen)
    end
  end
  return c
end

-- --- sheets ---------------------------------------------------------------------------
local urban, forest = {}, {}
local function add(list, name, canvas) list[#list + 1] = { name = name, canvas = canvas } end

add(urban, "road_a", road(1, true))
add(urban, "road_b", road(2, false))
add(urban, "road_cross_0", crossing(0))
add(urban, "road_cross_1", crossing(1))
add(urban, "road_kiosk_0", kiosk(0))
add(urban, "road_kiosk_1", kiosk(1))
build_sheet("urban", urban)

add(forest, "ground_a", ground(3))
add(forest, "ground_b", ground(4))
add(forest, "path", path())
add(forest, "fence", fence())
add(forest, "trans_urban_forest_0", transition(true, 0))
add(forest, "trans_urban_forest_1", transition(true, 1))
add(forest, "trans_forest_urban_0", transition(false, 0))
add(forest, "trans_forest_urban_1", transition(false, 1))
build_sheet("forest", forest)
