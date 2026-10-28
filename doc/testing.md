# Testing

## How testing works in this repo

Every hardware block we write lives in `src/rtl/<x>.sv` and gets its own **testbench** in
`src/tb/tb_<x>.sv`. A testbench is a small SystemVerilog module that has no ports: it
instantiates the block (the *device under test*, or DUT), drives its inputs, and compares
its outputs against values we know are correct.

The important word is **self-checking**. Nobody is expected to stare at waveforms to decide
whether a test passed. The testbench decides by itself, and it reports the verdict in the one
way a script can understand, the process exit code:

- on the first wrong value it calls `$fatal(1, "...")`, which stops the simulation and exits
  with an error;
- if it reaches the end without problems it prints `PASS` and calls `$finish`, which exits
  cleanly.

This matters because a testbench that only `$display`s "FAIL" still exits with success, so CI
would show a green tick on broken hardware. Always use `$fatal`.

[tb_sobel_alu.sv](../src/tb/tb_sobel_alu.sv) is the reference example: it contains a small
reference model of the Sobel operator, a `check` task that compares DUT and model, a list of
hand-picked corner cases, and then 100 000 random inputs with a fixed seed so that any failure
is reproducible.

### How a testbench gets compiled and run

We simulate with [Verilator](https://verilator.org), a free simulator that turns
SystemVerilog into a C++ program. To compile a testbench Verilator needs to know which files
belong to it, and that list is kept in a small text file, `sim/unit/tb_<x>.f`: one path per
line, written relative to the `sim/` folder (so they all start with `../`).

The [sim/Makefile](../sim/Makefile) has one generic rule, `vl_<name>`, that:

1. reads `sim/unit/<name>.f`;
2. compiles those files with Verilator, using the module called `<name>` as the top level
   (this is why the testbench module **must** be called exactly `tb_<x>`);
3. writes the compile output to `build/vl/<name>.log` (shown only if compilation fails);
4. runs the resulting executable, whose exit code is the test result.

`make -C sim unit_tests` simply runs that rule for every `.f` file found in `sim/unit/`. CI
(`.github/workflows/rtl-tests.yml`) runs the same target, so **adding a `.f` file is all it
takes to put a test in CI**: no workflow edits needed.

### Lint

Besides simulation, `make -C sim lint` runs `verilator --lint-only` on the RTL listed in every
`.f` file (testbench files are skipped). Lint catches bugs that simulate "fine" but are wrong
in hardware: width mismatches, accidental latches, signals driven from two places. It runs
first in CI and a lint error fails the build, so it is worth running locally before pushing.

### End-to-end check

`make -C sim check_ss` runs the full accelerator testbench (`tb_student_ss`) on a test image and
compares the result with a Python golden model
([check_sobel.py](../sim/check_sobel.py)); border pixels replicate the edge. This is the test
that tells us the whole pipeline works, not just one block.

### Command summary (run from the repo root)

| Command | What it does |
|---------|--------------|
| `make -C sim unit_tests` | build and run every testbench in `sim/unit/` |
| `make -C sim vl_tb_<x>` | build and run one testbench |
| `make -C sim lint` | lint the RTL of every `.f` file |
| `make -C sim check_ss` | full accelerator vs golden Sobel |

---

## Tutorial: add a test for your new component

Follow the steps in order and don't skip any. Every command runs from the **repo root** (the
folder that contains `src/`, `sim/` and `doc/`).

In this tutorial your component is called **`my_block`**. Every time you see `my_block`,
replace it with your module's name, using exactly the same spelling.

### Step 0: check you have the tools

```sh
verilator --version
```

You need version 5 or newer (for example `Verilator 5.048`). If the command isn't found,
install Verilator first (`brew install verilator` on macOS,
`sudo apt-get install verilator` on Ubuntu).

### Step 1: check your RTL file

Your design must be in `src/rtl/my_block.sv` (a subfolder like `src/rtl/decoder/` is fine too),
and the module inside must have the same name as the file:

```systemverilog
module my_block ( ... );
```

Lint it on its own:

```sh
verilator --lint-only src/rtl/my_block.sv
```

- **No output** means it's clean. Go to step 2.
- `Cannot find file containing module: 'something'` means `my_block` uses another module.
  Add that module's file to the command, e.g.
  `verilator --lint-only src/rtl/my_block.sv src/rtl/something.sv`, and write down that file:
  you'll need it in step 3.
- Any `%Warning-...` or `%Error-...` is a real problem in your RTL. Fix it before going on.

### Step 2: create the testbench

Create a new file **`src/tb/tb_my_block.sv`** and paste this template:

```systemverilog
// Self-checking testbench for my_block.
`timescale 1ns/1ps
module tb_my_block;

    // (A) One signal for every port of my_block: same name, same width.
    logic       clk     = 0;
    logic       rst_n   = 0;
    logic [7:0] in_data = 0;   // TODO: replace with your inputs (start them at 0)
    logic [7:0] out_data;      // TODO: replace with your outputs

    int n_checks = 0;

    // (B) The device under test. (.*) connects each port to the signal with the same name.
    my_block dut (.*);

    // (C) 10 ns clock. Delete this line if my_block has no clock.
    always #5 clk = ~clk;

    // (D) Compare one value, stop everything on the first mismatch.
    task automatic check(string what, logic [31:0] got, logic [31:0] exp);
        n_checks++;
        if (got !== exp)
            $fatal(1, "%s: got %0d, expected %0d (t=%0t)", what, got, exp, $time);
    endtask

    initial begin
        // (E) Reset for two clock cycles, then release it.
        repeat (2) @(posedge clk);
        #1;
        rst_n = 1;

        // (F) Your tests: set inputs, wait one clock, check outputs.
        //     TODO: replace with real cases for my_block.
        in_data = 8'd42;
        @(posedge clk); #1;
        check("out_data", out_data, 42);

        // (G) Only reached if every check passed.
        $display("PASS: %0d checks", n_checks);
        $finish;
    end

endmodule
```

Now edit it for your block:

1. **Line `module tb_my_block;`**: the name must be `tb_` + your module name, exactly.
2. **Section (A)**: open `src/rtl/my_block.sv`, look at its port list, and declare one
   `logic` per port with the **same name and width**. Inputs get `= 0`, outputs don't.
   If your block has no `clk`/`rst_n`, delete them.
3. **Section (B)**: change `my_block` to your module name. If your module has parameters
   you want to set, write `my_block #(.WIDTH(8)) dut (.*);`.
4. **Section (C)**: delete it if there's no clock.
5. **Section (E)**: if there's no reset, delete the `rst_n = 1;` line. If there's no clock,
   replace the whole section with `#1;`.
6. **Section (F)**: this is where the real work is. For every behaviour you want to verify:
   set the inputs, wait (`@(posedge clk); #1;` for clocked logic, just `#1;` for
   combinational logic), then call `check("signal name", signal, expected_value)`.
   Good things to test: the reset value, the normal case, the edge values (0, the maximum,
   wrap-arounds, saturation), and if possible many random inputs compared against a
   reference model (see how [tb_sobel_alu.sv](../src/tb/tb_sobel_alu.sv) does it).
7. **Don't touch section (D) and (G).** They make the test self-checking.

> Outputs wider than 32 bits: change `logic [31:0]` in the `check` task to a width big
> enough for your widest signal.

### Step 3: register the test

Create a new file **`sim/unit/tb_my_block.f`** (the name must be the testbench name + `.f`)
containing the RTL file, any extra file you noted in step 1, and the testbench last:

```
../src/rtl/my_block.sv
../src/tb/tb_my_block.sv
```

Rules for this file:

- paths are relative to the `sim/` folder, so they start with `../`;
- one file per line, no comments;
- if `my_block` uses other modules, list their files too (e.g. `../src/rtl/something.sv`);
- if you use a SystemVerilog `package`, put its file **first**.

### Step 4: run your test

```sh
make -C sim vl_tb_my_block
```

The first run takes a few seconds to compile. A passing test ends like this:

```
PASS: 2 checks
- ../src/tb/tb_my_block.sv:40: Verilog $finish
```

If you see `PASS`, go to step 5. Otherwise look up the message in the
[troubleshooting](#troubleshooting) table below.

### Step 5: make sure the test can actually fail

A test that can never fail is worse than no test. In section (F), change one expected value to
something wrong (e.g. `42` to `41`) and run step 4 again. You must see:

```
%Fatal: ../src/tb/tb_my_block.sv:23: Assertion failed in tb_my_block.check: out_data: got 42, expected 41 ...
make: *** [vl_tb_my_block] Error 1
```

Then **put the correct value back** and run step 4 once more to see `PASS` again.

### Step 6: run lint and all the tests

```sh
make -C sim lint
make -C sim unit_tests
```

`lint` must print no `%Warning` or `%Error` for your files, and `unit_tests` must show your
`PASS` line among the others.

### Step 7: commit and push

```sh
git add src/rtl/my_block.sv src/tb/tb_my_block.sv sim/unit/tb_my_block.f
git commit -m "add my_block and its testbench"
git push
```

Open a pull request. CI (the **rtl-tests** check on the PR page) runs lint and every unit test,
yours included, automatically. If it goes red, click **Details** to see which step failed; the
full logs are also attached to the run as the `sim-output` artifact.

### Done: checklist

- [ ] `src/rtl/my_block.sv` contains `module my_block` and passes `verilator --lint-only`
- [ ] `src/tb/tb_my_block.sv` contains `module tb_my_block`
- [ ] the testbench uses `$fatal` for errors and ends with `$display("PASS ...")` + `$finish`
- [ ] `sim/unit/tb_my_block.f` lists every file needed, with paths starting with `../`
- [ ] `make -C sim vl_tb_my_block` prints `PASS`
- [ ] breaking an expected value makes it fail (and you put it back)
- [ ] `make -C sim lint` is clean

### Troubleshooting

| You see | What it means | Fix |
|---------|---------------|-----|
| `No rule to make target 'vl_tb_my_block'` | `sim/unit/tb_my_block.f` doesn't exist or is named differently | Check the file name in step 3 |
| `Specified --top-module 'tb_my_block' was not found` | The module inside the testbench has a different name | Line 3 of the testbench must be `module tb_my_block;` |
| `Cannot find file containing module: 'xyz'` | A module used by your design isn't in the `.f` file | Add `../src/rtl/xyz.sv` (or wherever it lives) to the `.f` |
| `Cannot find file containing module: '../src/...sv'` | A path in the `.f` file is wrong | Check spelling and folder; paths are relative to `sim/` |
| `Can't find definition of variable: 'xyz'` | A port name in section (A) doesn't match the RTL | Make the names in (A) identical to the module's ports |
| The test never ends | `$finish` is never reached (the clock keeps the simulation alive forever) | Stop with Ctrl+C; check that (G) is there and that no `@(...)` waits for something that never happens |
| `PASS` printed but you expected a failure | Your check doesn't compare the right thing, or the wait is missing | Check you wait (`#1` / `@(posedge clk); #1;`) before `check`, and that step 5 really fails |
| CI is red but it passes locally | Usually a file not committed, or lint | Run `git status` and `make -C sim lint` |
