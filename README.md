# FPGA Examples (Tang Primer 20K Dock)

Open-source toolchain: Yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader.

## Layout
- `examples/Blinky` – blink an LED
- `examples/LedChaser` – 4-LED chaser
- `examples/MusicPlayer` – I2S sine-voice music player
- `Template/` – starter project; copied by `NewProject.sh`
- `Boards/` – shared board constraints
- `Docs/` – board schematics
- `Common.mk` – shared build rules

## Usage
```
cd examples/Blinky
make        # synth + place&route + bitstream into Build/
make prog   # load to SRAM
make flash  # write to flash
make clean
```

## New project
```
./NewProject.sh MyDesign   # creates examples/MyDesign from Template/
```
