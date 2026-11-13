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
