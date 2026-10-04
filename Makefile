# Runner A.P.E.R - build
#   make        -> build/runner.dsk
#   make run    -> Caprice32 (snap) with auto RUN"DISC
#   make test   -> headless tests with ~/cpcemu
#   make DEBUG=1 -> border colours show raster time per routine
#   make gfx    -> palette, graphics and track chunks (src/data/) from gfx/png
#                  (or gfx/placeholder) and levels/chunks
#   make placeholders -> regenerate stand-in art in gfx/placeholder/
#   make loading -> loading screen from the painted art (assets/loading/loading_art.jpg)
#   make loading-blender -> loading screen from the Blender scene instead

RASM    ?= rasm
IDSK    ?= iDSK
EMU     ?= /snap/bin/caprice32.launcher
PYTHON  ?= python3
CPCEMU  ?= $(HOME)/cpcemu
DEBUG   ?= 0

BUILD   := build
LOAD    := 4000
SRC     := $(filter-out src/loader.asm,$(wildcard src/*.asm))
GFX_IN  := $(wildcard gfx/png/*.png gfx/png/*.json gfx/placeholder/*.png gfx/placeholder/*.json levels/chunks/*.txt text/*.txt music/*.txt) \
           assets/loading/loading_cpc.png assets/loading/loading_palette.txt
GFX_TOOLS := tools/cpcpalette.py tools/assets.py tools/png2cpc.py tools/mklevel.py tools/mktext.py tools/mkmusic.py \
             tools/scr2cpc.py
GFX_STAMP := src/data/.stamp

BIN     := $(BUILD)/aper.bin
BANKS   := $(BUILD)/aperb4.bin $(BUILD)/aperb5.bin $(BUILD)/aperb6.bin $(BUILD)/aperb7.bin
LDR     := $(BUILD)/loader.bin $(BUILD)/loadscr.bin
LOADER  := src/disc.bas
SYM     := $(BUILD)/aper.sym
DSK     := $(BUILD)/runner.dsk

.PHONY: all run test clean gfx placeholders screenshots loading loading-blender

all: $(DSK)

$(BUILD):
	mkdir -p $@

gfx: $(GFX_STAMP)

$(GFX_STAMP): $(GFX_IN) $(GFX_TOOLS)
	$(PYTHON) tools/cpcpalette.py
	$(PYTHON) tools/png2cpc.py
	$(PYTHON) tools/mklevel.py
	$(PYTHON) tools/mktext.py
	$(PYTHON) tools/mkmusic.py
	$(PYTHON) tools/scr2cpc.py
	touch $@

placeholders:
	$(PYTHON) tools/mkplaceholders.py

# loading screen: the painted art -> CPC inks, or the Blender render
# (BLENDER = blender.exe on WSL) -> CPC inks
loading:
	$(PYTHON) tools/art2loading.py

BLENDER ?= blender
loading-blender:
	$(BLENDER) -b --factory-startup -P tools/blender/loading_scene.py -- assets/loading
	$(PYTHON) tools/quantize_loading.py

# src/main.asm SAVEs the main binary and one file per bank
$(BIN) $(BANKS) $(SYM) &: $(SRC) $(GFX_STAMP) $(BUILD)/debug-$(DEBUG) | $(BUILD)
	$(RASM) src/main.asm -os $(SYM) -s -sl -sq -twe -DDEBUG=$(DEBUG)

# loader + packed loading screen
$(LDR) &: src/loader.asm src/lib/dzx0_standard.asm $(GFX_STAMP) | $(BUILD)
	$(RASM) src/loader.asm -twe

# rebuild when DEBUG changes
$(BUILD)/debug-$(DEBUG): | $(BUILD)
	rm -f $(BUILD)/debug-*
	touch $@

$(DSK): $(BIN) $(BANKS) $(LDR) $(LOADER) src/runner.bas
	rm -f $@
	$(IDSK) $@ -n
	printf 'APR0\r\n\032' > $(BUILD)/scores
	$(IDSK) $@ -i $(BUILD)/scores -t 0
	cp $(LOADER) $(BUILD)/disc
	$(IDSK) $@ -i $(BUILD)/disc -t 0
	cp src/runner.bas $(BUILD)/runner
	$(IDSK) $@ -i $(BUILD)/runner -t 0
	$(IDSK) $@ -i $(BUILD)/loader.bin -t 1 -c 8000 -e 8000
	$(IDSK) $@ -i $(BUILD)/loadscr.bin -t 1 -c 4000
	$(IDSK) $@ -i $(BIN) -t 1 -c $(LOAD) -e $(LOAD)
	$(IDSK) $@ -i $(BUILD)/aperb4.bin -t 1 -c 4000
	$(IDSK) $@ -i $(BUILD)/aperb5.bin -t 1 -c 4000
	$(IDSK) $@ -i $(BUILD)/aperb6.bin -t 1 -c 4000
	$(IDSK) $@ -i $(BUILD)/aperb7.bin -t 1 -c 4000

# The snap launcher forwards only two arguments, so autocmd uses the long form.
run: $(DSK)
	$(EMU) '--autocmd=run"disc' $(abspath $(DSK))

test: $(DSK)
	CPCEMU=$(CPCEMU) $(PYTHON) tools/tests/run_tests.py

clean:
	rm -rf $(BUILD) src/data

screenshots: $(DSK)
	CPCEMU=$(CPCEMU) $(PYTHON) tools/screenshots.py
