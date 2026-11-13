# Winograd RTL Datapath Modules
- `input_transform.sv`: Input transform unit (B^T * d * B)
- `winograd_mul_array.sv`: Parameterizable element-wise multiplier engine
- `channel_accumulator.sv`: Multi-channel partial sum accumulator
- `output_transform.sv`: Output transform unit (A^T * M * A)
- `controller.sv`: Datapath controller & FSM
- `winograd_accelerator_top.sv`: Top-level accelerator core

## Width and scaling contract

`winograd_top` derives the input transform width as `DATA_IN_WIDTH + 2`,
the product width as `V_WIDTH + U_WIDTH`, and the accumulator width as
`PROD_WIDTH + $clog2(MAX_CHANNELS)`. The output transform adds two bits
per dimension. Explicit width overrides must provide at least this headroom;
invalid configurations fail at simulation startup.

`MAX_CHANNELS` defaults to 4, preserving the original 36-bit accumulator.
Set it to the maximum number of contributions between `first_ch` and `last_ch`
(for example, 64 gives a 40-bit accumulator with default input widths).
The caller must not exceed this bound or interleave tiles in the single accumulator.

`SHIFT_BITS` is exposed at the top level and defaults to 6, matching weights
scaled by 64 in the vector generator. Zero disables rounding and shifting.
Positive shifts round by adding half a quantization step (ties toward positive
infinity). Saturation uses the configured signed `DATA_OUT_WIDTH` range.

`PARALLEL_DSPS` supports only 16; other values fail at simulation startup.
