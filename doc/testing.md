# Testing

## Rule

Every module `src/rtl/<x>.sv` has a self-checking testbench `src/tb/tb_<x>.sv`:

- `$fatal(1, "...")` on any mismatch
- `$finish` when everything passed

Template: [tb_sobel_alu.sv](../src/tb/tb_sobel_alu.sv).

## Register a test

List the files the testbench needs in `sim/unit/tb_<x>.f` (paths relative to `sim/`):

```
../src/rtl/<x>.sv
../src/tb/tb_<x>.sv
```

CI picks it up automatically: no workflow changes needed.

## Run (Verilator, from the repo root)

| Command | What |
|---------|------|
| `make -C sim unit_tests` | all testbenches |
| `make -C sim vl_tb_<x>` | one testbench |
| `make -C sim lint` | lint the RTL of every `.f` file |
| `make -C sim check_ss` | full accelerator vs golden Sobel ([check_sobel.py](../sim/check_sobel.py), border pixels replicate the edge) |
