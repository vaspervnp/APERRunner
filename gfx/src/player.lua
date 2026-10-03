-- =============================================================================
-- Sheets "player" and "shadows".
-- The runner is seen from above and behind (running up the screen): brown
-- hair, red T-shirt, orange backpack, jeans, white trainers. One parametric
-- figure drawn at 5 sizes (each +2 px wide, +2 lines high) so every size reads
-- as the same character closer to the camera. 1 px is kept free on every side
-- for the black outline.
-- =============================================================================

dofile(GFX .. "src\\common.lua")

local function round(v) return math.floor(v + 0.5) end

-- proportions for a canvas of w x h
local function body(w, h)
  local b = {}
  b.w, b.h = w, h
  b.cx = w // 2                                  -- legs split here
  b.head_w = math.max(4, round((w - 2) * 0.5) // 2 * 2)
  b.head_h = math.max(4, round(h * 0.22))
  b.head_x = b.cx - b.head_w // 2
  b.torso_top = 1 + b.head_h
  b.torso_h = round(h * 0.27)
  b.arm_w = (w >= 14) and 2 or 1
  b.torso_x0 = 1 + b.arm_w
  b.torso_x1 = w - 2 - b.arm_w
  b.legs_top = b.torso_top + b.torso_h
  b.leg_max = (h - 2) - b.legs_top + 1           -- lines down to h-2
  b.leg_w = math.max(2, (w - 2) // 4)
  return b
end

local function head(c, b, dx)
  local x0, x1 = b.head_x + dx, b.head_x + b.head_w - 1 + dx
  c:rect(x0, 1, x1, b.head_h, RED)               -- hair seen from behind
  c:px(x0, 1, CLEAR); c:px(x1, 1, CLEAR)         -- round the top
  c:hline(x0 + 1, x1 - 1, b.head_h, PINK)        -- neck
  c:px(x0, b.head_h - 1, PINK); c:px(x1, b.head_h - 1, PINK)   -- ears
  c:px(x0 + 1, 2, ORANGE)                        -- hair highlight
end

local function torso(c, b, dx)
  local x0, x1 = b.torso_x0 + dx, b.torso_x1 + dx
  local y0, y1 = b.torso_top, b.legs_top - 1
  c:rect(x0, y0, x1, y1, BRED)
  c:vline(x1, y0, y1, RED)                       -- shade on the right
  -- backpack
  local bw = math.max(2, b.head_w - 2)
  local bx = b.cx - bw // 2 + dx
  c:rect(bx, y0 + 1, bx + bw - 1, y1, ORANGE)
  c:hline(bx, bx + bw - 1, y0 + 1, OLIVE)        -- flap
  c:vline(bx + bw - 1, y0 + 2, y1, RED)
  c:px(bx - 1, y0, BLACK); c:px(bx + bw, y0, BLACK)   -- straps
end

-- one arm hanging from the shoulder; len = lines below the shoulder
local function arm(c, b, side, len, dx)
  local x0 = (side < 0) and 1 or (b.w - 1 - b.arm_w)
  x0 = x0 + dx
  local y0 = b.torso_top
  for y = y0, y0 + len - 1 do
    local pen = (y < y0 + 2) and BRED or PINK    -- sleeve, then skin
    c:rect(x0, y, x0 + b.arm_w - 1, y, pen)
  end
end

-- arm raised next to the head (jumping)
local function arm_up(c, b, side)
  local x0 = (side < 0) and 1 or (b.w - 1 - b.arm_w)
  for y = 1, b.torso_top + 1 do
    c:rect(x0, y, x0 + b.arm_w - 1, y, (y > b.torso_top - 1) and BRED or PINK)
  end
end

-- arm stretched sideways at shoulder height
local function arm_out(c, b, side)
  local y = b.torso_top + 1
  if side < 0 then c:hline(1, b.torso_x0 - 1, y, PINK); c:px(b.torso_x0 - 1, y, BRED)
  else c:hline(b.torso_x1 + 1, b.w - 2, y, PINK); c:px(b.torso_x1 + 1, y, BRED) end
end

local function leg(c, b, side, len, spread)
  local x0 = (side < 0) and (b.cx - b.leg_w - spread) or (b.cx + spread)
  local y0 = b.legs_top
  for y = y0, y0 + len - 1 do
    local last = (y == y0 + len - 1)
    c:rect(x0, y, x0 + b.leg_w - 1, y, last and WHITE or ((side < 0) and BBLUE or BLUE))
  end
  if len > 0 then c:px(x0 + b.leg_w - 1, y0 + len - 1, GREY) end   -- sole
end

local function runner(w, h, pose)
  local c = Canvas(w, h)
  local b = body(w, h)
  local long, short = b.leg_max, math.max(2, b.leg_max - 3)
  local arm_long = b.torso_h + 1
  local arm_short = math.max(2, b.torso_h - 1)

  if pose:match("^run") then
    local phase = tonumber(pose:sub(4))
    local L = ({ long, long - 1, short, long - 1 })[phase + 1]
    local R = ({ short, long - 1, long, long - 1 })[phase + 1]
    leg(c, b, -1, L, 0); leg(c, b, 1, R, 0)
    torso(c, b, 0); head(c, b, 0)
    arm(c, b, -1, (R == long) and arm_long or arm_short, 0)   -- arms swing opposite
    arm(c, b, 1, (L == long) and arm_long or arm_short, 0)
  elseif pose == "lean_l" or pose == "lean_r" then
    local d = (pose == "lean_l") and -1 or 1
    leg(c, b, -1, long - 1, 0); leg(c, b, 1, long - 1, 0)
    torso(c, b, d); head(c, b, d)
    if d < 0 then arm_out(c, b, 1); arm(c, b, -1, arm_short, 0)
    else arm_out(c, b, -1); arm(c, b, 1, arm_short, 0) end
  elseif pose == "jump_up" then                  -- knees tucked, arms up
    leg(c, b, -1, math.max(2, long - 3), 1); leg(c, b, 1, math.max(2, long - 3), 1)
    torso(c, b, 0); head(c, b, 0)
    arm_up(c, b, -1); arm_up(c, b, 1)
  elseif pose == "jump_down" then                -- legs reaching down, arms out
    leg(c, b, -1, long, 1); leg(c, b, 1, long, 1)
    torso(c, b, 0); head(c, b, 0)
    arm_out(c, b, -1); arm_out(c, b, 1)
  elseif pose == "jump" then                     -- top of the highest jump
    leg(c, b, -1, long - 1, 2); leg(c, b, 1, long - 1, 2)
    torso(c, b, 0); head(c, b, 0)
    arm_up(c, b, -1); arm_up(c, b, 1)
    arm_out(c, b, -1); arm_out(c, b, 1)
  elseif pose:match("^crash") then               -- sprawled on the ground
    leg(c, b, -1, long, 2); leg(c, b, 1, long, 2)
    torso(c, b, 0); head(c, b, 0)
    arm_out(c, b, -1); arm_out(c, b, 1)
    if pose == "crash1" then                     -- dizzy stars
      c:px(1, 1, YELLOW); c:px(w - 2, 2, YELLOW); c:px(2, b.head_h, WHITE)
      c:px(w - 3, 1, WHITE)
    end
  end
  outline(c, BLACK)
  return c
end

local function shadow(w, h)
  local c = Canvas(w, h)
  ellipse(c, 0, 0, w - 1, h - 1, BLACK)
  for y = 0, h - 1 do for x = 0, w - 1 do
    if (x + y) % 2 == 1 then c:px(x, y, CLEAR) end   -- 50% dither
  end end
  return c
end

-- --- sheets (manifest order, tools/assets.py PLAYER_FRAMES) ---------------------
local SIZES = { s1 = { 10, 16 }, s2 = { 12, 18 }, s3 = { 14, 20 }, s4 = { 16, 22 }, s5 = { 18, 24 } }
local ORDER = {
  { "s1", { "run0", "run1", "run2", "run3", "lean_l", "lean_r", "crash0", "crash1" } },
  { "s2", { "jump_up", "jump_down" } },
  { "s3", { "run0", "run1", "run2", "run3", "lean_l", "lean_r", "crash0", "crash1", "jump_up", "jump_down" } },
  { "s4", { "jump_up", "jump_down" } },
  { "s5", { "jump" } },
}

local frames = {}
for _, entry in ipairs(ORDER) do
  local size = SIZES[entry[1]]
  for _, pose in ipairs(entry[2]) do
    frames[#frames + 1] = { name = entry[1] .. "_" .. pose, canvas = runner(size[1], size[2], pose) }
  end
end
build_sheet("player", frames)

build_sheet("shadows", {
  { name = "sh1", canvas = shadow(8, 4) },
  { name = "sh2", canvas = shadow(10, 4) },
  { name = "sh3", canvas = shadow(12, 6) },
  { name = "sh4", canvas = shadow(14, 6) },
})
