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

## Sequential reuse across output filters

`winograd_top` now has a required `reuse_input` input. Tie it low for the original
streaming behavior. Each accepted normal channel computes V and stores it while
also processing that channel's weights. The most recent complete input-channel
group is retained in a cache of `MAX_CHANNELS * 16 * V_WIDTH` bits.

To compute another output filter for the same spatial tile:

1. Send the initial filter's channels with `reuse_input=0`, `first_ch` on channel
   zero, and `last_ch` on the final channel.
2. Send the next filter's transformed weights in the same channel order with
   `reuse_input=1` and the same first/last markers. `d_tile` is ignored, and the
   input transform is held idle during replay.
3. Repeat step 2 for further filters. Start a new spatial tile with a normal group.

Transfers occur only on `in_valid && in_ready`; hold data, mode, and markers while
waiting. Cache completion introduces one idle acceptance cycle between the last
normal channel and the first replay channel. Subsequent replay channels can be
accepted every cycle. Replay filters can follow each other without draining the
pipeline; there is still only one multiplier array and one channel accumulator.

Replay requests are held off (`in_ready=0`) until a full group is cached, and when
markers disagree with the cached channel count or an unfinished group. Reset
invalidates the cache and partial sums. A new normal group replaces the entire
cached tile. Normal groups must contain 1 through `MAX_CHANNELS` channels, without
interleaving filters; simulation checks their sequence and size.

The tile core implements transformed-input reuse. The streaming wrapper below
adds weight storage and line buffers. The cache uses an asynchronous read; FPGA
memory mapping, area, and timing need synthesis measurement.

## Streaming images with local weights

`winograd_stream_top` wraps the tile core with `line_buffer_2d`, transformed-weight
storage, and a filter/channel scheduler. Set `IMAGE_WIDTH`, `IMAGE_HEIGHT`,
`CHANNELS`, and `FILTERS` at elaboration. Dimensions must be at least 4.

1. Load each `(weight_filter, weight_channel)` once by sending a complete 4x4
   transformed `weight_tile` on `weight_valid && weight_ready`. Indices are
   zero-based. Weights use the same scale as the core (`SHIFT_BITS`, default 6).
2. Pulse `start` when `start_ready` is high. Missing weights prevent starting.
3. Stream signed pixels in `(row, column, input channel)` order, with channel
   varying fastest. Hold a pixel until `pixel_valid && pixel_ready`. Input gaps
   and downstream scheduling stalls are supported. Send all image pixels.
4. Consume every `out_valid` 2x2 tile. `out_row` and `out_col` identify its top-left
   output coordinates; `out_filter` identifies its output channel. Order is
   spatial raster order, then all filters for that position. There is no output
   backpressure; a consumer must accept every valid tile, as with the tile core.
5. `frame_done` pulses once all pixels and results have been processed. Start
   another frame without reloading weights, or replace weights while idle.

The wrapper performs stride-1, unpadded convolution and emits complete 2x2 output
tiles: `floor((IMAGE_HEIGHT-2)/2) * floor((IMAGE_WIDTH-2)/2)` per filter. If an
output dimension is odd, its final single row/column is omitted. Padding and
partial output tiles are not implemented. Reset aborts the current frame and
invalidates all weights; reload them before restarting. Writes during an active
frame and out-of-range weight addresses are rejected with `weight_ready=0`.

The line buffer retains three rows per input channel plus 4x4 horizontal windows,
reusing pixels both vertically and horizontally. Each pixel is accepted once per
frame. For each spatial position, filter zero fills the transformed-input cache;
remaining filters replay it. Weight storage holds `FILTERS * CHANNELS * 16` signed
values and reuses them across every spatial position and subsequent frames.
The existing `winograd_top` tile interface remains available separately.

The memories use asynchronous reads. Actual block-RAM mapping and clock frequency
require synthesis; synchronous block RAM would need additional read stages.
