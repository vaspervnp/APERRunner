-- =============================================================================
-- Sheets "items" (coins, power-ups) and "hud" (panel background, icons, bars).
-- Pen 14 (GLINT) is only used for the coin highlight: its colour is cycled.
-- The HUD background must be vertically uniform (every pixel column one
-- colour): the HUD scrolls in screen memory with the playfield.
-- =============================================================================

dofile(GFX .. "src\\common.lua")

-- --- coin: 4-frame spin, 8x8 --------------------------------------------------------
local function coin(frame)
  local c = Canvas(8, 8)
  local widths = { 8, 6, 2, 6 }
  local w = widths[frame + 1]
  local x0 = (8 - w) // 2
  if w == 2 then                               -- edge-on
    c:rect(3, 0, 4, 7, BLACK)
    c:vline(3, 1, 6, YELLOW)
    c:vline(4, 1, 6, OLIVE)
    c:px(3, 2, GLINT)
  else
    -- black rim so the coin reads on olive ballast, shaded right side
    ellipse(c, x0, 0, x0 + w - 1, 7, YELLOW, BLACK)
    for y = 1, 6 do
      local x = x0 + w - 2
      if c:get(x, y) == YELLOW then c:px(x, y, OLIVE) end
    end
    if w >= 6 then                             -- embossed "A" stroke
      c:vline(x0 + w // 2 - 1, 2, 5, OLIVE)
      c:vline(x0 + w // 2, 2, 5, OLIVE)
      c:hline(x0 + w // 2 - 1, x0 + w // 2, 4, YELLOW)
    end
    c:px(x0 + 1, 2, GLINT); c:px(x0 + 2, 1, GLINT)
  end
  return c
end

-- --- power-ups: 12x12 token with a white ring --------------------------------------
local function token(draw)
  local c = Canvas(12, 12)
  ellipse(c, 0, 0, 11, 11, BLACK)
  ellipse(c, 1, 1, 10, 10, WHITE)
  ellipse(c, 2, 2, 9, 9, BLUE)
  draw(c)
  return c
end

local POWERUPS = {
  pu_magnet = function(c)                      -- red horseshoe, white tips
    c:rect(3, 3, 4, 7, BRED); c:rect(7, 3, 8, 7, BRED)
    c:rect(3, 7, 8, 8, BRED)
    c:rect(3, 3, 4, 4, WHITE); c:rect(7, 3, 8, 4, WHITE)
  end,
  pu_turbo = function(c)                       -- double arrow up
    for i = 0, 2 do
      c:hline(5 - i, 6 + i, 3 + i, YELLOW)
      c:hline(5 - i, 6 + i, 6 + i, ORANGE)
    end
  end,
  pu_slow = function(c)                        -- turtle
    ellipse(c, 3, 3, 8, 8, GREEN)
    c:px(5, 5, LIME); c:px(6, 6, LIME)
    c:rect(5, 2, 6, 2, LIME)                   -- head
    c:px(3, 4, LIME); c:px(8, 4, LIME); c:px(3, 8, LIME); c:px(8, 8, LIME)
  end,
  pu_spring = function(c)                      -- coil spring
    for y = 3, 8 do c:hline(4, 7, y, (y % 2 == 0) and WHITE or GREY) end
    c:hline(3, 8, 9, BRED)
  end,
  pu_helmet = function(c)                      -- helmet seen from above
    ellipse(c, 3, 3, 8, 8, BBLUE)
    c:vline(5, 3, 8, WHITE); c:vline(6, 3, 8, WHITE)
    c:px(4, 4, SKY)
  end,
  pu_ticket = function(c)                      -- ticket marked x2
    c:rect(3, 3, 8, 8, WHITE)
    c:vline(4, 3, 8, BRED)
    c:px(6, 4, BLACK); c:px(7, 5, BLACK); c:px(6, 5, BLACK); c:px(7, 4, BLACK)   -- x
    c:hline(6, 7, 7, BLACK)                    -- 2 (stylised)
  end,
}

-- --- HUD ------------------------------------------------------------------------------
-- a dashboard: steel frame with the green ISAP stripe, a dark blue display
-- (bytes 2-19: where the values sit, pen 1) and on the right a little track
-- that scrolls with the world (sleepers every other row: hud_bg_t) and shows
-- the stations as they go by (hud_station).
local HUD_COLUMNS = {
  BLACK, GREY, WHITE, GREEN,                                   -- frame, ISAP stripe
  BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE,  -- the display
  BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE,
  BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE, BLUE,
  BLUE, BLUE, BLUE, BLUE, BLUE, BLUE,
  GREEN, BLACK,                                                -- stripe, then the track
  WHITE, OLIVE, OLIVE, WHITE,                                  -- rails on the ballast
  GREY, BLACK,                                                 -- frame
}
local TRACK_X = 42                                             -- left rail

local function hud_bg(kind)
  local c = Canvas(48, 8)
  assert(#HUD_COLUMNS == 48)
  for x = 0, 47 do c:vline(x, 0, 7, HUD_COLUMNS[x + 1]) end
  if kind == "sleeper" then
    c:rect(TRACK_X, 3, TRACK_X + 3, 5, RED)                    -- a sleeper across the rails
  elseif kind == "station" then                                -- a station board
    c:rect(40, 0, 46, 7, WHITE)
    c:rect(41, 1, 45, 6, BBLUE)
    c:hline(42, 44, 2, WHITE); c:px(43, 3, WHITE); c:hline(42, 44, 4, WHITE)   -- a little sign
    c:hline(42, 44, 5, WHITE)
  end
  return c
end

local function icon(draw)
  local c = Canvas(8, 8)
  draw(c)
  return c
end

local ICONS = {
  ic_coin = function(c) ellipse(c, 1, 0, 6, 7, YELLOW, OLIVE); c:px(2, 2, GLINT) end,
  ic_magnet = function(c)
    c:rect(1, 1, 2, 5, BRED); c:rect(5, 1, 6, 5, BRED); c:rect(1, 5, 6, 6, BRED)
    c:rect(1, 1, 2, 2, WHITE); c:rect(5, 1, 6, 2, WHITE)
  end,
  ic_turbo = function(c)
    for i = 0, 2 do c:hline(3 - i, 4 + i, i, YELLOW); c:hline(3 - i, 4 + i, i + 4, ORANGE) end
  end,
  ic_slow = function(c) ellipse(c, 1, 1, 6, 6, GREEN, BLACK); c:rect(3, 0, 4, 0, LIME); c:px(3, 3, LIME) end,
  ic_spring = function(c) for y = 1, 5 do c:hline(2, 5, y, (y % 2 == 0) and WHITE or GREY) end; c:hline(1, 6, 6, BRED) end,
  ic_helmet = function(c) ellipse(c, 1, 1, 6, 6, BBLUE, BLACK); c:vline(3, 1, 6, WHITE); c:vline(4, 1, 6, WHITE) end,
  ic_ticket = function(c) c:rect(0, 1, 7, 6, WHITE); c:vline(1, 1, 6, BRED); c:px(4, 3, BLACK); c:px(5, 4, BLACK); c:px(5, 3, BLACK); c:px(4, 4, BLACK) end,
  ic_life = function(c)                        -- the runner's head from behind
    c:rect(2, 0, 5, 4, RED); c:px(2, 0, CLEAR); c:px(5, 0, CLEAR)
    c:hline(3, 4, 4, PINK); c:px(2, 3, PINK); c:px(5, 3, PINK)
    c:rect(1, 5, 6, 7, BRED); c:rect(3, 5, 4, 7, ORANGE)
  end,
  ic_dist = function(c)                        -- rails
    c:vline(1, 0, 7, WHITE); c:vline(6, 0, 7, WHITE)
    for y = 1, 7, 3 do c:hline(0, 7, y, RED) end
    c:vline(1, 0, 7, WHITE); c:vline(6, 0, 7, WHITE)
  end,
}

-- a power-up not running: its icon in grey and black on the display
local function dim(draw)
  local c = icon(draw)
  for y = 0, 7 do for x = 0, 7 do
    local p = c:get(x, y)
    if p ~= CLEAR then c:px(x, y, (p == BLACK) and BLACK or GREY) end
  end end
  return c
end

local function bar(full)
  local c = Canvas(2, 8)
  if full then c:rect(0, 0, 1, 7, YELLOW); c:vline(1, 0, 7, ORANGE)
  else c:rect(0, 0, 1, 7, BLUE); c:hline(0, 1, 7, BLACK) end
  return c
end

-- digits 0-9: 3x7 white on the panel, in a 4x8 cell (gap right and below)
local DIGITS = {
  { "###", "#.#", "#.#", "#.#", "#.#", "#.#", "###" },
  { ".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###" },
  { "###", "..#", "..#", "###", "#..", "#..", "###" },
  { "###", "..#", "..#", ".##", "..#", "..#", "###" },
  { "#.#", "#.#", "#.#", "###", "..#", "..#", "..#" },
  { "###", "#..", "#..", "###", "..#", "..#", "###" },
  { "###", "#..", "#..", "###", "#.#", "#.#", "###" },
  { "###", "..#", "..#", "..#", ".#.", ".#.", ".#." },
  { "###", "#.#", "#.#", "###", "#.#", "#.#", "###" },
  { "###", "#.#", "#.#", "###", "..#", "..#", "###" },
}

local function digit(d, pen)
  local c = Canvas(4, 8, BLUE)
  for y, row in ipairs(DIGITS[d + 1]) do
    for x = 1, 3 do
      if row:sub(x, x) == "#" then c:px(x - 1, y - 1, pen or WHITE) end
    end
  end
  return c
end

-- --- sheets ---------------------------------------------------------------------------
local items = {}
for i = 0, 3 do items[#items + 1] = { name = "coin" .. i, canvas = coin(i) } end
for _, name in ipairs({ "pu_magnet", "pu_turbo", "pu_slow", "pu_spring", "pu_helmet", "pu_ticket" }) do
  items[#items + 1] = { name = name, canvas = token(POWERUPS[name]) }
end
build_sheet("items", items)

local hud = { { name = "hud_bg", canvas = hud_bg() }, { name = "hud_bg_t", canvas = hud_bg("sleeper") },
              { name = "hud_station", canvas = hud_bg("station") } }
local POWERUP_ICONS = { "ic_magnet", "ic_turbo", "ic_slow", "ic_spring", "ic_helmet", "ic_ticket" }
for _, name in ipairs({ "ic_coin", table.unpack(POWERUP_ICONS) }) do
  hud[#hud + 1] = { name = name, canvas = icon(ICONS[name]) }
end
for _, name in ipairs(POWERUP_ICONS) do
  hud[#hud + 1] = { name = name .. "_off", canvas = dim(ICONS[name]) }
end
for _, name in ipairs({ "ic_life", "ic_dist" }) do
  hud[#hud + 1] = { name = name, canvas = icon(ICONS[name]) }
end

hud[#hud + 1] = { name = "bar_full", canvas = bar(true) }
hud[#hud + 1] = { name = "bar_empty", canvas = bar(false) }
for d = 0, 9 do hud[#hud + 1] = { name = "d" .. d, canvas = digit(d) } end
for d = 0, 9 do hud[#hud + 1] = { name = "h" .. d, canvas = digit(d, ORANGE) } end   -- the best score
build_sheet("hud", hud)
