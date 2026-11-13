# Testbenches & Verification
- `input_transform_tb.sv`: Unit test for input transform
- `multiplier_array_tb.sv`: Unit test for multiplier array
- `accumulator_tb.sv`: Unit test for channel accumulator
- `output_transform_tb.sv`: Unit test for output transform
- `winograd_core_tb.sv`: Full regression testbench for Winograd top-level
- `direct_conv_tb.sv`: Direct convolution baseline testbench

- `parameter_widths_tb.sv`: Derived widths, 64-channel full-range accumulation,
  zero-shift output, and signed 8-bit saturation. Run with assertions enabled:

```sh
verilator --binary --assert --timing -Wno-fatal --top-module parameter_widths_tb --Mdir /tmp/winograd_widths_obj rtl/*.sv tb/parameter_widths_tb.sv
/tmp/winograd_widths_obj/Vparameter_widths_tb
```

Run the complete regression from the repository root:

```sh
python3 tb/run_regression.py
```

Requires Python with NumPy, Verilator, and a C++ toolchain. The runner generates
vectors and builds in temporary directories, leaving checked-in hex files intact.
It checks 50 tiles each with 1 channel, 4 channels without gaps, 4 channels with
input gaps, and 64 channels with gaps. Tiles are sent without draining the pipeline;
invalid cycles deliberately carry channel markers to check that they are ignored.
It also runs the parameter-width test and 21 output-transform cases covering
positive/negative rounding ties, saturation boundaries, and zero-shift operation.
A deliberately corrupted expected pixel must produce a nonzero simulator exit.

`winograd_core_tb` accepts `CIN` and `INSERT_GAPS` parameters and a
`+VECTOR_DIR=<directory>` argument (default `tb`). Generate matching vectors when
changing `CIN`. Mismatches, extra outputs, and watchdog timeouts use `$fatal`.

The regression also verifies that `PARALLEL_DSPS=4` and `8` fail at startup.
