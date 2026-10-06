# Γραφικά Runner A.P.E.R

Όλα τα γραφικά είναι **mode 0** (pixel 2:1), με την παλέτα του παιχνιδιού
(`palette/aper_game.gpl`, από το `tools/cpcpalette.py`).

## Ροή

```
gfx/src/<script>.lua  --(Aseprite MCP: run_lua_script)-->  gfx/src/<sheet>.aseprite
                                                           gfx/png/<sheet>.png + .json
gfx/png/*  --(make gfx: tools/png2cpc.py)-->  src/data/gfx_<asset>.asm
```

Εκτέλεση ενός script στον Aseprite (τρέχει στα Windows, το repo φαίνεται μέσω `\\wsl.localhost`):

```lua
GFX = "\\\\wsl.localhost\\Ubuntu\\home\\vasilhs\\repos\\APERRunner\\gfx\\"
dofile(GFX .. "src\\track.lua")
```

Τα `.lua` είναι η πηγή· τα `.aseprite` και τα `png/` παράγονται από αυτά (μπορούν να διορθωθούν και
χειροκίνητα στον Aseprite — τότε το `.lua` παύει να είναι η αλήθεια για εκείνο το sheet).
Τα `placeholder/` χρησιμοποιούνται μόνο αν λείπει ένα sheet από το `png/`.

## Sheets

| Script | Sheet | Frames | Μέγεθος (px mode 0) | Είδος |
|---|---|---|---|---|
| `track.lua` | `track` | 36: ράγες ×2, στοπ ×2, φανάρι ×2, 3 βαγόνια ×5, 3 μηχανές ×3, ράμπα ανόδου ×3, καθόδου ×3 | 28×8 | tile |
| `sides.lua` | `urban` | 6: δρόμος ×2, διάβαση ×2, περίπτερο ×2 (αριστερή πλευρά· η δεξιά = mirror) | 30×8 | tile |
| `sides.lua` | `forest` | 8: έδαφος ×2, μονοπάτι, φράχτης, μεταβάσεις ×4 | 30×8 | tile |
| `overlays.lua` | `urban_ov` | αυτοκίνητα ×3, ταξί (8×16), λεωφορείο, τρόλεϊ (8×32) | 8×16 / 8×32 | sprite |
| `overlays.lua` | `forest_ov` | πεύκο 16×24, βελανιδιά 24×24, κυπαρίσσι 8×24, θάμνος 8×8, βράχος 8×8 | διάφορα | sprite |
| `platform.lua` | `platform` | 11 γραμμές αποβάθρας: τσιμέντο, αρμός, παγκάκι ×3, στέγαστρο ×2, πινακίδα ×2, ράμπα, σκιά | 14×1 | rows |
| `bridges.lua` | `bridges` | πεζογέφυρα ×3 + σκιά, γέφυρα αυτοκινήτων ×6 + σκιά | 144×8 | lines (γραμμές ως εντολές) |
| `player.lua` | `player` | s1 (10×16) ×8, s2 (12×18) ×2, s3 (14×20) ×10, s4 (16×22) ×2, s5 (18×24) ×1 | διάφορα | sprite |
| `player.lua` | `shadows` | 4 ελλείψεις 8×4 … 14×6 | διάφορα | sprite |
| `items.lua` | `items` | νόμισμα ×4 (8×8), power-ups ×6 (12×12) | διάφορα | sprite |
| `items.lua` | `hud` | φόντο 48×8 (**κάθετα ομοιόμορφο**), εικονίδια ×9 (8×8), μπάρες ×2 (2×8) | διάφορα | tile/sprite |

Σε sheets με frames διαφορετικών μεγεθών, ο καμβάς έχει το μέγιστο μέγεθος και κάθε frame βρίσκεται
πάνω-αριστερά· το `png2cpc.py` κόβει στο μέγεθος του `tools/assets.py` και ελέγχει ότι το υπόλοιπο είναι διάφανο.

## Κανόνες

- Σειρά «0» ενός αντικειμένου πολλών σειρών = η πιο κοντινή στον παίκτη (κάτω).
- Pen 14 (λάμψη νομίσματος) και pen 15 (λάμπα φαναριού) είναι δεσμευμένα: τα χρώματά τους εναλλάσσονται.
- Φως από πάνω-αριστερά, σκιές κάτω-δεξιά.
- Εργαλεία ελέγχου: `tools/preview.py` (στήλες tiles), `tools/mockup.py` (σκηνή παιχνιδιού), `make test`.

## Εκκρεμεί

- Γραμματοσειρές (6×8, 8×16) και οθόνες μενού/σκορ (Φάσεις 7–8).
- Loading screen: `prompts/blender_loading_screen.md` (Φάση 8).
