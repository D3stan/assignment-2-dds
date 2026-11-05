# Nexys A7-100T bitstream (base-line)

Built on MSI with Vivado 2026.1 from commit 9fa97ea (`base-line`), firmware `pixel_inversion` (254-word IMEM init, drives the custom Sobel accelerator).

- `DidacticNexys_A7.bit` / `.bin`: program the board.
- `reports/`: full Vivado reports (`utilization`, `utilization_pct`, `timing*`, `check_timing`, synth/impl logs).

## Resources (xc7a100tcsg324-1)

| Resource | Used | Available | Util % |
|---|---|---|---|
| Slice LUTs | 25403 | 63400 | 40.07 |
| - LUT as logic | 17211 | 63400 | 27.15 |
| - LUT as distributed RAM | 8192 | 19000 | 43.12 |
| Slice registers | 16238 | 126800 | 12.81 |
| F7 / F8 muxes | 6968 / 700 | 31700 / 15850 | 21.98 / 4.42 |
| Slices | 10937 | 15850 | 69.00 |
| Block RAM tiles | 64 | 135 | 47.41 |
| DSPs | 1 | 240 | 0.42 |
| Bonded IOB | 43 | 210 | 20.48 |

## Timing

All constraints met: WNS +22.943 ns, WHS +0.030 ns, WPWS +2.633 ns (0 failing endpoints).
