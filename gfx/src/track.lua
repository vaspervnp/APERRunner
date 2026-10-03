-- =============================================================================
-- Sheet "track": 28x8 lane tiles (tools/assets.py TRACK_TILES).
-- Top-down, light from the top-left. Index 0 of multi-row objects is the row
-- nearest the player (bottom of the screen).
-- =============================================================================

dofile(GFX .. "src\\common.lua")

local W, H = 28, 8
local RAIL_X = { 6, 20 }                -- 2 px rails, 14 px gauge
local SLEEPER_Y = { 1, 5 }              -- every 4 lines, same phase on every tile

local function ballast(c, seed)
  for y = 0, H - 1 do for x = 0, W - 1 do
    local n = noise(x, y, seed)
    -- calm gravel: mostly olive, some grey stones, few dark gaps (no red:
    -- red is reserved for the sleepers so they read clearly)
    local pen = OLIVE
    if n < 0.18 then pen = GREY elseif n < 0.24 then pen = BLACK end
    c:px(x, y, pen)
  end end
end

local function sleepers(c, missing)
  for i, y in ipairs(SLEEPER_Y) do
    if i ~= missing then
      c:hline(3, 24, y, RED)
      c:px(3, y, BLACK)
      c:px(24, y, BLACK)
      for x = 4, 25 do if x % 2 == 0 then c:px(x, y + 1, BLACK) end end   -- shadow
    end
  end
end

local function rails(c)
  for _, x in ipairs(RAIL_X) do
    c:vline(x, 0, H - 1, WHITE)
    c:vline(x + 1, 0, H - 1, GREY)
    c:vline(x + 2, 0, H - 1, BLACK)
  end
end

local function track(seed, missing)
  local c = Canvas(W, H)
  ballast(c, seed)
  sleepers(c, missing)
  rails(c)
  return c
end

-- --- trains: roof seen from above, x 2..25 --------------------------------------
local LIVERY = {
  [1] = { base = GREEN, light = LIME, dark = BLACK, stripe = WHITE },   -- classic green
  [2] = { base = WHITE, light = WHITE, dark = GREY, stripe = BBLUE },   -- white, blue band
  [3] = { base = RED, light = ORANGE, dark = BLACK, stripe = YELLOW },  -- vintage red/ochre
}

local function roof(c, t, y0, y1)
  local l = LIVERY[t]
  for y = y0, y1 do
    c:px(2, y, BLACK)
    c:px(3, y, l.light)
    c:hline(4, 23, y, l.base)
    c:px(5, y, l.stripe)
    c:px(22, y, l.stripe)
    c:px(24, y, l.dark == BLACK and GREY or l.dark)
    c:px(25, y, BLACK)
  end
  -- roof ridge highlight
  for y = y0, y1 do c:px(13, y, l.light) end
end

local function car_end(c, t, at_bottom)
  -- rounded end on the last two lines; ballast shows at the corners
  local l = LIVERY[t]
  local e, e2 = 7, 6
  c:hline(4, 23, e2, l.dark == BLACK and GREY or l.dark)
  c:hline(3, 24, e, BLACK)
  c:px(2, e2, BLACK); c:px(25, e2, BLACK)
  c:px(2, e, OLIVE); c:px(25, e, OLIVE)
  c:hline(8, 19, e2, BLACK)                     -- gangway door seen from above
  c:hline(9, 18, e2, GREY)
end

local function wagon(t, part)
  local c = track(10 + t, nil)
  local l = LIVERY[t]
  if part == "coupler" then
    c:rect(11, 0, 16, H - 1, BLACK)              -- bellows between cars
    for y = 0, H - 1, 2 do c:hline(12, 15, y, GREY) end
    return c
  end
  roof(c, t, 0, H - 1)
  if part == "body_a" then                       -- air conditioning unit
    c:rect(8, 1, 19, 6, GREY)
    c:hline(8, 19, 1, WHITE)
    c:vline(8, 1, 6, WHITE)
    c:hline(9, 20, 7, BLACK)
    c:vline(20, 2, 7, BLACK)
    for x = 10, 17, 2 do c:vline(x, 3, 5, BLACK) end
  elseif part == "body_b" then                   -- roof vents
    for _, x0 in ipairs({ 7, 16 }) do
      c:rect(x0, 2, x0 + 4, 4, l.dark == BLACK and BLACK or GREY)
      c:hline(x0, x0 + 4, 2, GREY)
      c:hline(x0 + 1, x0 + 5, 5, BLACK)
    end
  elseif part == "end_bottom" then
    car_end(c, t)
  elseif part == "end_top" then
    car_end(c, t)
    c:flip_v()
  end
  return c
end

local function loco(t, part)
  if part == "nose_top" then                     -- cab facing up (loco at the rear of a train)
    local c = loco(t, "nose")
    c:flip_v()
    return c
  end
  local c = track(20 + t, nil)
  local l = LIVERY[t]
  roof(c, t, 0, H - 1)
  if part == "nose" then
    -- cab front facing the player: windscreen, headlights, buffer beam
    c:rect(5, 2, 22, 4, SKY)
    c:hline(5, 22, 1, BLACK)
    c:hline(5, 22, 5, BLACK)
    c:vline(13, 2, 4, BLACK)
    c:vline(14, 2, 4, BLACK)
    c:px(6, 2, WHITE); c:px(16, 2, WHITE)
    c:hline(3, 24, 6, l.stripe == WHITE and YELLOW or l.stripe)
    c:rect(4, 6, 5, 6, YELLOW); c:rect(22, 6, 23, 6, YELLOW)
    c:hline(3, 24, 7, BLACK)
    c:px(2, 7, OLIVE); c:px(25, 7, OLIVE)
  elseif part == "body" then                     -- resistor grilles
    c:rect(7, 0, 20, 7, BLACK)
    for y = 0, 7, 2 do c:hline(8, 19, y, GREY) end
    c:vline(7, 0, 7, WHITE)
  elseif part == "pantograph" then
    c:hline(4, 23, 3, GREY)                      -- collector bar
    c:hline(4, 23, 4, BLACK)
    for i = 0, 3 do                              -- diamond frame
      c:px(9 + i, 3 - i, BLACK); c:px(18 - i, 3 - i, BLACK)
      c:px(9 + i, 4 + i, BLACK); c:px(18 - i, 4 + i, BLACK)
    end
    c:rect(12, 0, 15, 0, GREY)
    c:rect(12, 7, 15, 7, GREY)
  end
  return c
end

-- --- buffer stop (2 rows) ------------------------------------------------------
local function stop(index)
  local c = track(30 + index, nil)
  if index == 0 then                             -- striped beam facing the player
    for x = 2, 25 do c:vline(x, 2, 5, ((x // 3) % 2 == 0) and BRED or WHITE) end
    c:hline(2, 25, 1, BLACK)
    c:hline(2, 25, 6, BLACK)
    c:px(2, 7, BLACK); c:px(25, 7, BLACK)
    for x = 3, 26, 2 do c:px(x, 7, BLACK) end   -- shadow
    c:rect(5, 3, 6, 4, BLACK); c:rect(21, 3, 22, 4, BLACK)   -- buffers
  else                                           -- concrete block behind it
    c:rect(4, 0, 23, 7, GREY)
    c:hline(4, 23, 0, WHITE)
    c:vline(4, 0, 7, WHITE)
    c:vline(24, 0, 7, BLACK)
    for x = 6, 21, 4 do c:rect(x, 3, x + 1, 4, YELLOW) end
    for x = 8, 21, 4 do c:rect(x, 3, x + 1, 4, BLACK) end
  end
  return c
end

-- --- signal gantry (2 rows), lamp uses the cycled LAMP pen -----------------------
local function signal(index)
  local c = track(40 + index, nil)
  if index == 0 then
    c:rect(0, 2, 27, 4, GREY)                    -- beam across the lane
    c:hline(0, 27, 2, WHITE)
    c:hline(0, 27, 5, BLACK)
    c:rect(0, 1, 1, 6, BLACK); c:rect(26, 1, 27, 6, BLACK)   -- legs
    c:rect(10, 1, 17, 6, BLACK)                  -- signal head
    c:rect(12, 2, 15, 5, LAMP)
    c:px(12, 2, WHITE)
  else                                           -- stop line + beam shadow
    c:hline(3, 24, 6, WHITE)
    for x = 0, 27, 2 do c:px(x, 0, BLACK) end
  end
  return c
end

-- --- ramps (3 rows): darker at the ground end, brighter at the roof end ----------
local SHADES = { BLUE, GREY, WHITE }

local function ramp(up, index)
  local c = track(50 + index, nil)
  local level = up and index or (2 - index)      -- 0 = ground end, 2 = roof end
  for y = 0, H - 1 do
    -- 24 lines from ground (0) to roof (23), measured towards the roof end
    local along = up and (level * 8 + (7 - y)) or (level * 8 + y)
    local band = along / 8                       -- 0..3
    local low = math.min(2, math.floor(band))
    local high = math.min(2, low + 1)
    local frac = band - math.floor(band)
    for x = 3, 24 do
      local pen = SHADES[low + 1]
      if frac > 0.5 and (x + y) % 2 == 0 then pen = SHADES[high + 1] end
      c:px(x, y, pen)
    end
    if along % 3 == 0 then c:hline(5, 22, y, BLACK) end   -- grip ribs
    c:px(2, y, BLACK); c:px(25, y, BLACK)
    if y % 2 == 0 then c:px(3, y, WHITE); c:px(24, y, WHITE) end   -- railings
  end
  if level == 0 then                             -- hazard stripes at the ground lip
    local y = up and 7 or 0
    for x = 3, 24 do c:px(x, y, ((x // 2) % 2 == 0) and YELLOW or BLACK) end
  end
  return c
end

-- --- sheet in manifest order -----------------------------------------------------
local frames = {}
local function add(name, canvas) frames[#frames + 1] = { name = name, canvas = canvas } end

add("rail_a", track(1, nil))
add("rail_b", track(2, 2))                       -- worn: one sleeper missing
add("stop_0", stop(0)); add("stop_1", stop(1))
add("signal_0", signal(0)); add("signal_1", signal(1))
for t = 1, 3 do
  for _, part in ipairs({ "end_bottom", "body_a", "body_b", "end_top", "coupler" }) do
    add("wagon" .. t .. "_" .. part, wagon(t, part))
  end
end
for t = 1, 3 do
  for _, part in ipairs({ "nose", "body", "pantograph", "nose_top" }) do
    add("loco" .. t .. "_" .. part, loco(t, part))
  end
end
for i = 0, 2 do add("ramp_up_" .. i, ramp(true, i)) end
for i = 0, 2 do add("ramp_down_" .. i, ramp(false, i)) end

build_sheet("track", frames)
