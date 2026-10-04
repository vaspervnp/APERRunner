-- =============================================================================
-- Sheet "font": 6x8 cells (3 bytes in mode 0), glyphs 5x7 at the top-left,
-- white on transparent. Latin capitals, digits, the Greek capitals that do
-- not look like Latin ones, punctuation and arrows (tools/assets.py FONT).
-- =============================================================================

dofile(GFX .. "src\\common.lua")

dofile(GFX .. "src\\font_glyphs.lua")
local G = FONT_GLYPHS

-- order = tools/assets.py FONT_GLYPHS
local ORDER = { " ", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
  "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
  "GAMMA", "DELTA", "THETA", "LAMBDA", "XI", "PI", "SIGMA", "PHI", "PSI", "OMEGA",
  "DOT", "COLON", "MINUS", "EXCL", "QUEST", "SLASH", "LEFT", "RIGHT", "UP", "DOWN" }

local frames = {}
for _, key in ipairs(ORDER) do
  local c = Canvas(6, 8)
  for y, row in ipairs(G[key]) do
    for x = 1, 5 do
      if row:sub(x, x) == "#" then c:px(x - 1, y - 1, WHITE) end
    end
  end
  local name = (key == " ") and "space" or (("0123456789"):find(key, 1, true) and ("n" .. key) or key:lower())
  frames[#frames + 1] = { name = name, canvas = c }
end
build_sheet("font", frames)
