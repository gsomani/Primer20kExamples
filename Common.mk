buildDir = Build
DEVICE   = GW2A-LV18PG256C8/I7
FAMILY   = GW2A-18
PACK_DEV = GW2A-18
BOARD    = tangprimer20k
FREQ_MHZ = 27

src      = $(top).v
cst      = $(top).cst
synthOut = $(buildDir)/$(top).json
pnrOut   = $(buildDir)/$(top)Pnr.json
bitstream = $(buildDir)/$(top).fs

.PHONY: all synth pnr pack prog flash clean

all: pack

# Step 1: synthesis (Yosys): Verilog -> netlist JSON
synth: $(synthOut)
$(synthOut): $(src) | $(buildDir)
	yosys -q -p "read_verilog $(src); synth_gowin -top $(top) -json $@"

# Step 2: place and route (nextpnr-himbaechel): netlist -> routed JSON
pnr: $(pnrOut)
$(pnrOut): $(synthOut) $(cst)
	nextpnr-himbaechel --json $< --write $@ \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) --vopt cst=$(cst) \
		--freq $(FREQ_MHZ)

# Step 3: bitstream (gowin_pack): routed JSON -> .fs
pack: $(bitstream)
$(bitstream): $(pnrOut)
	gowin_pack -d $(PACK_DEV) -o $@ $<

# Step 4a: load into SRAM (lost at power-off)
prog: $(bitstream)
	openFPGALoader -b $(BOARD) $<

# Step 4b: write to flash (persists across power cycles)
flash: $(bitstream)
	openFPGALoader -b $(BOARD) -f $<

$(buildDir):
	mkdir -p $@

clean:
	rm -rf $(buildDir)
