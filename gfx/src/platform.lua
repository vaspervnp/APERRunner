-- =============================================================================
-- Sheet "platform": the station platforms, as 14x1 lines (x 0 = side pixel
-- 16, x 13 = next to lane 1; the right side is mirrored by tools/png2cpc.py).
-- src/platform.asm builds each platform row from these lines (and lines of
-- the side tile under it, at the ends): concrete with a yellow tactile line
-- and a white edge, benches, a red tiled canopy with blue name boards.
-- =============================================================================

dofile(GFX .. "src\\common.lua")

local lines = {
  -- name           pens 0-F, x 16..29
  { "concrete",     "32222222772230" },
  { "joint",        "33333333773330" },
  { "bench_seat",   "32555552772230" },
  { "bench_back",   "32444440772230" },
  { "bench_shadow", "32200000772230" },
  { "roof_a",       "3DDDDDDDDDD030" },
  { "roof_b",       "34444444444030" },
  { "sign_edge",    "3D33333333D030" },
  { "sign_text",    "3DB3B33B3BD030" },
  { "ramp",         "37070707070730" },
  { "roof_shadow",  "30000000000030" },
}

local frames = {}
for _, l in ipairs(lines) do
  local c = Canvas(14, 1)
  c:map(0, 0, { l[2] })
  frames[#frames + 1] = { name = l[1], canvas = c }
end
build_sheet("platform", frames)
