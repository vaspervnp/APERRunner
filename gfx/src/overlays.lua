-- =============================================================================
-- Sheets "urban_ov" (vehicles, 8 px wide = one traffic lane) and
-- "forest_ov" (trees, bushes, rocks): masked sprites baked into the scenery
-- when a row is generated. Vehicles face down the screen (front at the bottom).
-- =============================================================================

dofile(GFX .. "src\\common.lua")

-- --- vehicles ---------------------------------------------------------------------
-- body colour, roof highlight
local CAR = {
  car_red = { BRED, PINK }, car_blue = { BBLUE, SKY }, car_white = { WHITE, WHITE },
  taxi = { YELLOW, WHITE },
}

local function car(name)
  local body, light = CAR[name][1], CAR[name][2]
  local c = Canvas(8, 16)
  c:rect(1, 0, 6, 15, body)                  -- body with rounded corners
  c:rect(0, 1, 7, 14, body)
  c:vline(0, 1, 14, BLACK); c:vline(7, 1, 14, BLACK)
  c:hline(1, 6, 0, BLACK); c:hline(1, 6, 15, BLACK)
  c:rect(0, 3, 0, 4, BLACK); c:rect(7, 3, 7, 4, BLACK)       -- wheels
  c:rect(0, 11, 0, 12, BLACK); c:rect(7, 11, 7, 12, BLACK)
  c:rect(2, 2, 5, 3, BLUE)                   -- rear window
  c:rect(2, 4, 5, 9, body)                   -- roof
  c:vline(2, 4, 9, light)
  c:rect(2, 10, 5, 12, SKY)                  -- windscreen
  c:px(2, 10, WHITE)
  c:px(1, 14, YELLOW); c:px(6, 14, YELLOW)   -- headlights
  c:px(1, 1, BRED); c:px(6, 1, BRED)         -- tail lights
  if name == "taxi" then
    c:rect(3, 6, 4, 7, WHITE)                -- TAXI sign
    c:hline(3, 4, 7, BLACK)
  end
  return c
end

local function bus(trolley)
  local body = trolley and YELLOW or BBLUE
  local c = Canvas(8, 32)
  c:rect(0, 0, 7, 31, body)
  c:vline(0, 0, 31, BLACK); c:vline(7, 0, 31, BLACK)
  c:hline(0, 7, 0, BLACK); c:hline(0, 7, 31, BLACK)
  c:rect(1, 28, 6, 29, SKY)                  -- windscreen at the front (bottom)
  c:px(1, 28, WHITE)
  c:px(1, 30, WHITE); c:px(6, 30, WHITE)     -- headlights
  if trolley then
    c:rect(1, 2, 6, 26, YELLOW)
    c:vline(2, 2, 22, BLACK)                 -- trolley poles towards the back
    c:vline(5, 2, 22, BLACK)
    c:rect(2, 22, 5, 25, GREY)               -- pole base
    c:rect(2, 10, 5, 12, ORANGE)
  else
    c:rect(1, 2, 6, 26, WHITE)               -- white roof, blue band
    for y = 4, 24, 5 do c:rect(2, y, 5, y + 1, GREY) end   -- roof vents
    c:vline(1, 2, 26, BBLUE); c:vline(6, 2, 26, BBLUE)
  end
  return c
end

-- --- trees -------------------------------------------------------------------------
-- canopy seen from above: light body (the ground is dark green), shaded
-- bottom-right, leaf clumps, black rim
local function canopy(c, x0, y0, x1, y1, seed)
  ellipse(c, x0, y0, x1, y1, LIME)
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  local rx, ry = (x1 - x0 + 1) / 2, (y1 - y0 + 1) / 2
  for y = y0, y1 do for x = x0, x1 do
    if c:get(x, y) == LIME then
      local dx, dy = (x - cx) / rx, (y - cy) / ry
      local n = noise(x // 2, y // 2, seed)
      if dx + dy > 0.8 then c:px(x, y, (n < 0.6) and BLACK or GREEN)
      elseif dx + dy > 0.1 and n < 0.55 then c:px(x, y, GREEN)
      elseif n < 0.15 then c:px(x, y, GREEN)
      elseif dx + dy < -0.9 and n > 0.85 then c:px(x, y, YELLOW) end
    end
  end end
  outline(c, BLACK)
end

local function pine()
  local c = Canvas(16, 24)
  -- tiered crown seen from above: alternating light/dark rings, jagged edge
  for y = 0, 21 do
    local t = math.abs(y - 10.5) / 11
    local half = math.floor((1 - t * t) * 7 + ((y % 3 == 0) and 1 or 0))
    for x = 8 - half, 7 + half do
      local r = math.sqrt(((x - 7.5) / 8) ^ 2 + ((y - 10.5) / 11) ^ 2)
      local ring = math.floor(r * 6)
      c:px(x, y, (ring % 2 == 0) and LIME or GREEN)
    end
  end
  for y = 11, 21 do for x = 9, 15 do
    if c:get(x, y) ~= CLEAR and (x + y) % 2 == 0 then c:px(x, y, BLACK) end
  end end
  c:rect(7, 10, 8, 11, OLIVE)                -- tip
  outline(c, BLACK)
  for x = 9, 13 do c:px(x, 22, BLACK) end    -- shadow
  return c
end

local function oak()
  local c = Canvas(24, 24)
  canopy(c, 1, 1, 22, 21, 5)
  for x = 6, 20, 2 do c:px(x, 23, BLACK) end -- shadow
  return c
end

local function cypress()
  local c = Canvas(8, 24)
  ellipse(c, 1, 0, 6, 21, LIME)
  for y = 0, 21 do for x = 1, 6 do
    if c:get(x, y) == LIME and (x >= 4 or y % 3 == 0) then c:px(x, y, GREEN) end
  end end
  for y = 6, 20, 2 do c:px(5, y, BLACK) end
  outline(c, BLACK)
  c:px(5, 23, BLACK); c:px(6, 22, BLACK)
  return c
end

local function bush()
  local c = Canvas(8, 8)
  canopy(c, 0, 0, 7, 6, 9)
  return c
end

local function rock()
  local c = Canvas(8, 8)
  ellipse(c, 0, 1, 7, 6, GREY)
  c:hline(2, 4, 2, WHITE)
  c:px(1, 3, WHITE)
  c:hline(4, 6, 5, BLACK)
  outline(c, BLACK)
  return c
end

-- --- sheets ---------------------------------------------------------------------------
local urban_ov = {
  { name = "car_red", canvas = car("car_red") },
  { name = "car_blue", canvas = car("car_blue") },
  { name = "car_white", canvas = car("car_white") },
  { name = "taxi", canvas = car("taxi") },
  { name = "bus", canvas = bus(false) },
  { name = "trolley", canvas = bus(true) },
}
build_sheet("urban_ov", urban_ov)

local forest_ov = {
  { name = "pine", canvas = pine() },
  { name = "oak", canvas = oak() },
  { name = "cypress", canvas = cypress() },
  { name = "bush", canvas = bush() },
  { name = "rock", canvas = rock() },
}
build_sheet("forest_ov", forest_ov)
