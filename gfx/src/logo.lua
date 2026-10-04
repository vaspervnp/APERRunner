-- =============================================================================
-- Sheet "logo": 144x48 title "RUNNER" / "A.P.E.R" for the menu (opaque,
-- black background). Letters are the 5x7 font glyphs scaled up, with a dark
-- outline and a drop shadow.
-- =============================================================================

dofile(GFX .. "src\\common.lua")
dofile(GFX .. "src\\font_glyphs.lua")

local W, H = 144, 48
local c = Canvas(W, H, BLACK)

-- draws text scaled (sx, sy) with top-left (x0, y0); fill(gy) gives the pen
-- for glyph row gy (0-6); returns the width used
local function text(str, x0, y0, sx, sy, gap, fill, shadow)
  local x = x0
  for i = 1, #str do
    local ch = str:sub(i, i)
    local key = (ch == ".") and "DOT" or ch
    local g = FONT_GLYPHS[key]
    local cols = (ch == ".") and 3 or 5
    local first = (ch == ".") and 1 or 1
    for pass = 1, 2 do
      for gy = 1, 7 do
        for gx = first, first + cols - 1 do
          if g[gy]:sub(gx, gx) == "#" then
            for dy = 0, sy - 1 do for dx = 0, sx - 1 do
              local px, py = x + (gx - first) * sx + dx, y0 + (gy - 1) * sy + dy
              if pass == 1 then c:px(px + 1, py + 2, shadow)
              else c:px(px, py, fill(gy - 1)) end
            end end
          end
        end
      end
    end
    x = x + cols * sx + gap
  end
  return x - x0 - gap
end

-- dark outline around everything that is not black/shadow
local function outline_letters(letters)
  local copy = c.img:clone()
  for y = 0, H - 1 do for x = 0, W - 1 do
    local p = copy:getPixel(x, y)
    if p == BLACK or p == RED then
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and ny >= 0 and nx < W and ny < H then
          local q = copy:getPixel(nx, ny)
          if letters[q] then c:px(x, y, BLUE); break end
        end
      end
    end
  end end
end

local function runner_fill(gy) return (gy < 3) and YELLOW or ((gy < 5) and ORANGE or BRED) end
local function aper_fill(gy) return (gy < 4) and WHITE or GREY end

local w1 = 6 * 10 + 5 * 2                      -- "RUNNER": 2x3 pixels per dot
text("RUNNER", (W - w1) // 2, 2, 2, 3, 2, runner_fill, RED)
local w2 = 4 * 10 + 3 * 6 + 6 * 2               -- "A.P.E.R": 2x2 pixels per dot
text("A.P.E.R", (W - w2) // 2, 28, 2, 2, 2, aper_fill, GREEN)
outline_letters({ [YELLOW] = true, [ORANGE] = true, [BRED] = true, [WHITE] = true, [GREY] = true })

-- rails under the title
for x = 8, W - 9 do c:px(x, 45, GREY); c:px(x, 47, GREY) end
for x = 10, W - 11, 6 do c:px(x, 46, RED); c:px(x + 1, 46, RED) end

build_sheet("logo", { { name = "logo", canvas = c } })
