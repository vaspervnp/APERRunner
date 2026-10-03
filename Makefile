# Runner A.P.E.R - build
#   make        -> build/aper.dsk
#   make run    -> Caprice32 (snap) with auto RUN"DISC
#   make test   -> headless tests with ~/cpcemu
#   make DEBUG=1 -> border colours show raster time per routine
#   make gfx    -> palette, graphics and track chunks (src/data/) from gfx/png
#                  (or gfx/placeholder) and levels/chunks
#   make placeholders -> regenerate stand-in art in gfx/placeholder/

RASM    ?= rasm
IDSK    ?= iDSK
EMU     ?= /snap/bin/caprice32.launcher
PYTHON  ?= python3
CPCEMU  ?= $(HOME)/cpcemu
DEBUG   ?= 0

BUILD   := build
LOAD    := 4000
SRC     := $(wildcard src/*.asm)
GFX_IN  := $(wildcard gfx/png/*.png gfx/png/*.json gfx/placeholder/*.png gfx/placeholder/*.json levels/chunks/*.txt)
GFX_TOOLS := tools/cpcpalette.py tools/assets.py tools/png2cpc.py tools/mklevel.py
GFX_STAMP := src/data/.stamp

BIN     := $(BUILD)/aper.bin
BANKS   := $(BUILD)/aperb4.bin $(BUILD)/aperb5.bin
LOADER  := src/disc.bas
SYM     := $(BUILD)/aper.sym
DSK     := $(BUILD)/aper.dsk

.PHONY: all run test clean gfx placeholders

all: $(DSK)

$(BUILD):
	mkdir -p $@

gfx: $(GFX_STAMP)

$(GFX_STAMP): $(GFX_IN) $(GFX_TOOLS)
	$(PYTHON) tools/cpcpalette.py
	$(PYTHON) tools/png2cpc.py
	$(PYTHON) tools/mklevel.py
	touch $@

placeholders:
	$(PYTHON) tools/mkplaceholders.py

# src/main.asm SAVEs the main binary and one file per bank
$(BIN) $(BANKS) $(SYM) &: $(SRC) $(GFX_STAMP) $(BUILD)/debug-$(DEBUG) | $(BUILD)
	$(RASM) src/main.asm -os $(SYM) -s -sl -sq -twe -DDEBUG=$(DEBUG)

# rebuild when DEBUG changes
$(BUILD)/debug-$(DEBUG): | $(BUILD)
	rm -f $(BUILD)/debug-*
	touch $@

$(DSK): $(BIN) $(BANKS) $(LOADER)
	rm -f $@
	$(IDSK) $@ -n
	cp $(LOADER) $(BUILD)/disc
	$(IDSK) $@ -i $(BUILD)/disc -t 0
	$(IDSK) $@ -i $(BIN) -t 1 -c $(LOAD) -e $(LOAD)
	$(IDSK) $@ -i $(BUILD)/aperb4.bin -t 1 -c 4000
	$(IDSK) $@ -i $(BUILD)/aperb5.bin -t 1 -c 4000

# The snap launcher forwards only two arguments, so autocmd uses the long form.
run: $(DSK)
	$(EMU) '--autocmd=run"disc' $(abspath $(DSK))

test: $(DSK)
	CPCEMU=$(CPCEMU) $(PYTHON) tools/tests/run_tests.py

clean:
	rm -rf $(BUILD) src/data
