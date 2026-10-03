-- =============================================================================
-- Shared helpers for the Runner A.P.E.R Aseprite sheet scripts.
-- Run through the Aseprite MCP (Aseprite runs on Windows, the repo is reached
-- through \\wsl.localhost\...):
--   dofile(GFX .. "src\\track.lua")
-- Each sheet script builds an indexed sprite (game palette + transparent
-- index 16, pixel ratio 2:1, one frame and one tag per tile), saves
-- gfx/src/<sheet>.aseprite and exports gfx/png/<sheet>.png + .json.
-- =============================================================================

GFX = GFX or "\\\\wsl.localhost\\Ubuntu\\home\\vasilhs\\repos\\APERRunner\\gfx\\"

-- pens (plan.md 2.5)
BLACK, BLUE, GREY, WHITE, RED, ORANGE, OLIVE, YELLOW = 0, 1, 2, 3, 4, 5, 6, 7
GREEN, LIME, SKY, BBLUE, PINK, BRED, GLINT, LAMP = 8, 9, 10, 11, 12, 13, 14, 15
CLEAR = 16

function game_palette()
  local pal = Palette{ fromFile = GFX .. "palette\\aper_game.gpl" }
  pal:resize(17)
  pal:setColor(CLEAR, Color{ r = 255, g = 0, b = 255, a = 0 })
  return pal
end

-- deterministic noise in [0,1)
function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + (seed or 0) * 2147483647) % 4294967296
  n = ((n ~ (n >> 13)) * 1274126177) % 4294967296
  return (n % 10007) / 10007
end

-- a drawing surface for one frame
function Canvas(w, h, fill)
  local c = { w = w, h = h, img = Image(w, h, ColorMode.INDEXED) }
  c.img:clear(fill or CLEAR)
  function c:px(x, y, pen)
    if x >= 0 and y >= 0 and x < self.w and y < self.h then self.img:putPixel(x, y, pen) end
  end
  function c:get(x, y) return self.img:getPixel(x, y) end
  function c:rect(x0, y0, x1, y1, pen)
    for y = y0, y1 do for x = x0, x1 do self:px(x, y, pen) end end
  end
  function c:hline(x0, x1, y, pen) self:rect(x0, y, x1, y, pen) end
  function c:vline(x, y0, y1, pen) self:rect(x, y0, x, y1, pen) end
  function c:dither(x0, y0, x1, y1, pen_a, pen_b, phase)
    for y = y0, y1 do for x = x0, x1 do
      self:px(x, y, ((x + y + (phase or 0)) % 2 == 0) and pen_a or pen_b)
    end end
  end
  -- draw rows of pen characters: 0-9 A-F, '.' = leave as is
  function c:map(x0, y0, rows)
    for dy, row in ipairs(rows) do
      for dx = 1, #row do
        local ch = row:sub(dx, dx)
        if ch ~= "." then self:px(x0 + dx - 1, y0 + dy - 1, tonumber(ch, 16)) end
      end
    end
  end
  function c:flip_v()
    local copy = self.img:clone()
    for y = 0, self.h - 1 do for x = 0, self.w - 1 do
      self.img:putPixel(x, y, copy:getPixel(x, self.h - 1 - y))
    end end
  end
  return c
end

-- filled ellipse inside (x0,y0)-(x1,y1); outline pen optional
function ellipse(c, x0, y0, x1, y1, pen, outline)
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  local rx, ry = (x1 - x0 + 1) / 2, (y1 - y0 + 1) / 2
  for y = y0, y1 do for x = x0, x1 do
    local dx, dy = (x + 0.5 - (cx + 0.5)) / rx, (y + 0.5 - (cy + 0.5)) / ry
    if dx * dx + dy * dy <= 1.0 then c:px(x, y, pen) end
  end end
  if outline then
    for y = y0, y1 do for x = x0, x1 do
      local inside = function(px, py)
        if px < x0 or px > x1 or py < y0 or py > y1 then return false end
        local dx, dy = (px + 0.5 - (cx + 0.5)) / rx, (py + 0.5 - (cy + 0.5)) / ry
        return dx * dx + dy * dy <= 1.0
      end
      if inside(x, y) and not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1)) then
        c:px(x, y, outline)
      end
    end end
  end
end

-- black outline around the opaque pixels of a sprite canvas (inside its box)
function outline(c, pen)
  local copy = c.img:clone()
  local function solid(x, y)
    return x >= 0 and y >= 0 and x < c.w and y < c.h and copy:getPixel(x, y) ~= CLEAR
  end
  for y = 0, c.h - 1 do for x = 0, c.w - 1 do
    if not solid(x, y) and (solid(x - 1, y) or solid(x + 1, y) or solid(x, y - 1) or solid(x, y + 1)) then
      c:px(x, y, pen or BLACK)
    end
  end end
end

-- frames: list of { name = ..., canvas = Canvas }. Frames smaller than the
-- largest one sit at the top-left of their cel (tools/png2cpc.py crops them
-- to the size in tools/assets.py).
function build_sheet(sheet, frames)
  local w, h = 0, 0
  for _, f in ipairs(frames) do w = math.max(w, f.canvas.w); h = math.max(h, f.canvas.h) end
  local spr = Sprite(w, h, ColorMode.INDEXED)
  spr:setPalette(game_palette())
  spr.transparentColor = CLEAR
  spr.pixelRatio = Size(2, 1)
  local layer = spr.layers[1]
  layer.name = sheet
  for i = 2, #frames do spr:newEmptyFrame() end
  for i, f in ipairs(frames) do
    local img = Image(w, h, ColorMode.INDEXED)
    img:clear(CLEAR)
    -- copy pixel by pixel: drawImage would skip index 0 (black) as transparent
    for y = 0, f.canvas.h - 1 do for x = 0, f.canvas.w - 1 do
      img:putPixel(x, y, f.canvas.img:getPixel(x, y))
    end end
    spr:newCel(layer, i, img, Point(0, 0))
    local tag = spr:newTag(i, i)
    tag.name = f.name
  end
  spr:saveAs(GFX .. "src\\" .. sheet .. ".aseprite")
  app.command.ExportSpriteSheet{
    ui = false, askOverwrite = false,
    type = SpriteSheetType.HORIZONTAL,
    textureFilename = GFX .. "png\\" .. sheet .. ".png",
    dataFilename = GFX .. "png\\" .. sheet .. ".json",
    dataFormat = SpriteSheetDataFormat.JSON_ARRAY,
    filenameFormat = "{tag}",
    trim = false, openGenerated = false,
  }
  print(sheet .. ": " .. #frames .. " frames, canvas " .. w .. "x" .. h)
  spr:close()
end
