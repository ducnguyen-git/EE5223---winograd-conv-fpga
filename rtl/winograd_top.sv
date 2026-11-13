// =============================================================================
// Module: winograd_top
// Description: Top-Level Pipelined Winograd F(2x2, 3x3) CNN Accelerator Core
// Precision:
//   - Input Activations: Signed 16-bit
//   - Transformed Weights U: Signed 16-bit
//   - Transformed Inputs V: Signed 18-bit
//   - Intermediate Multipliers: Signed 34-bit
//   - Accumulated Partial Sums: Signed 36-bit
//   - Output Tile: Signed 16-bit (2x2)
// Throughput: 1 Tile output per pipeline cycle once primed
// =============================================================================
`timescale 1ns / 1ps

module winograd_top #(
    parameter MAX_CHANNELS  = 4,
    parameter DATA_IN_WIDTH = 16,
    parameter V_WIDTH       = DATA_IN_WIDTH + 2,
    parameter U_WIDTH       = 16,
    parameter PROD_WIDTH    = V_WIDTH + U_WIDTH,
    parameter ACCUM_WIDTH   = PROD_WIDTH + $clog2(MAX_CHANNELS),
    parameter DATA_OUT_WIDTH= 16,
    parameter PARALLEL_DSPS = 16,
    parameter SHIFT_BITS    = 6
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // Input Control & Data Handshakes
    input  logic                            in_valid,
    output logic                            in_ready,
    input  logic signed [DATA_IN_WIDTH-1:0] d_tile [0:3][0:3],
    input  logic signed [U_WIDTH-1:0]       u_tile [0:3][0:3],
    input  logic                            first_ch,
    input  logic                            last_ch,
    input  logic                            reuse_input, // Replay cached V; d_tile is ignored.

    // Output Handshakes & Data
    output logic                            out_valid,
    output logic signed [DATA_OUT_WIDTH-1:0] y_tile [0:1][0:1]
);

    initial begin
        if (DATA_IN_WIDTH < 1 || U_WIDTH < 1 || V_WIDTH < DATA_IN_WIDTH + 2 ||
            PROD_WIDTH < V_WIDTH + U_WIDTH)
            $fatal(1, "Invalid Winograd input/product widths");
    end

    localparam CACHE_INDEX_BITS = (MAX_CHANNELS > 1) ? $clog2(MAX_CHANNELS) : 1;
    localparam CHANNEL_BITS = $clog2(MAX_CHANNELS + 1);
    logic [CHANNEL_BITS-1:0] next_channel, channel_in, channel_d1, cached_channels;
    logic cache_ready, group_active, group_reuse;
    logic accepted, accepted_d1, reuse_d1;
    // shortcut: asynchronous cache reads; add a read stage when synchronous RAM is needed.
    logic signed [V_WIDTH-1:0] v_cache [0:MAX_CHANNELS-1][0:3][0:3];
    logic signed [V_WIDTH-1:0] mult_v [0:3][0:3];

    assign channel_in = first_ch ? '0 : next_channel;
    // Replay must match the complete cached channel group, in order.
    assign in_ready = reuse_input ?
        (cache_ready && (!group_active || group_reuse) &&
         (int'(channel_in) < int'(cached_channels)) &&
         (first_ch == !group_active) &&
         (last_ch == (channel_in == cached_channels - 1'b1))) :
        (!group_active || !group_reuse);
    assign accepted = in_valid && in_ready;

    // -------------------------------------------------------------------------
    // Stage 1 & 2: Input Transform Unit (V = B^T * d * B)
    // Latency: 1 cycle
    // -------------------------------------------------------------------------
    logic                          v_trans_valid;
    logic signed [V_WIDTH-1:0]     v_matrix [0:3][0:3];

    input_transform_2d #(
        .DATA_IN_WIDTH(DATA_IN_WIDTH),
        .INTER_WIDTH(DATA_IN_WIDTH + 1),
        .DATA_OUT_WIDTH(V_WIDTH)
    ) u_input_trans (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(accepted && !reuse_input),
        .d_in(d_tile),
        .valid_out(v_trans_valid),
        .v_out(v_matrix)
    );

    // Delay match u_tile, first_ch, last_ch by 1 cycle to align with V transform output
    logic signed [U_WIDTH-1:0] u_tile_d1 [0:3][0:3];
    logic                      first_ch_d1;
    logic                      last_ch_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_ch_d1 <= 1'b0;
            last_ch_d1  <= 1'b0;
            for (int r = 0; r < 4; r = r + 1) begin
                for (int c = 0; c < 4; c = c + 1) begin
                    u_tile_d1[r][c] <= '0;
                end
            end
        end else begin
            first_ch_d1 <= first_ch;
            last_ch_d1  <= last_ch;
            u_tile_d1   <= u_tile;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_channel <= '0;
            channel_d1 <= '0;
            cached_channels <= '0;
            cache_ready <= 1'b0;
            group_active <= 1'b0;
            group_reuse <= 1'b0;
            accepted_d1 <= 1'b0;
            reuse_d1 <= 1'b0;
        end else begin
            accepted_d1 <= accepted;
            if (accepted) begin
                channel_d1 <= channel_in;
                reuse_d1 <= reuse_input;
                next_channel <= last_ch ? '0 : channel_in + 1'b1;
                group_active <= !last_ch;
                group_reuse <= reuse_input;
            end
            if (v_trans_valid) begin
                v_cache[CACHE_INDEX_BITS'(channel_d1)] <= v_matrix;
                if (last_ch_d1) begin
                    cached_channels <= channel_d1 + 1'b1;
                    cache_ready <= 1'b1;
                end
            end
            // A replacement tile invalidates the old cache until every channel is stored.
            if (accepted && !reuse_input && first_ch)
                cache_ready <= 1'b0;
        end
    end

    assign mult_v = reuse_d1 ? v_cache[CACHE_INDEX_BITS'(channel_d1)] : v_matrix;

    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n && accepted && !reuse_input) begin
            if (int'(channel_in) >= MAX_CHANNELS || first_ch != !group_active)
                $fatal(1, "Invalid input channel sequence or MAX_CHANNELS exceeded");
        end
    end
    // synthesis translate_on

    // -------------------------------------------------------------------------
    // Stage 3: Multiplier Array (M = U .* V)
    // Latency: 1 cycle
    // -------------------------------------------------------------------------
    logic                          mult_valid;
    logic signed [PROD_WIDTH-1:0]  m_matrix [0:3][0:3];

    multiplier_array #(
        .V_WIDTH(V_WIDTH),
        .U_WIDTH(U_WIDTH),
        .PROD_WIDTH(PROD_WIDTH),
        .PARALLEL_DSPS(PARALLEL_DSPS)
    ) u_mult_array (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(accepted_d1),
        .v_in(mult_v),
        .u_in(u_tile_d1),
        .valid_out(mult_valid),
        .m_out(m_matrix)
    );

    // Delay match first_ch_d1, last_ch_d1 by 1 cycle to align with multiplier output
    logic first_ch_d2;
    logic last_ch_d2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_ch_d2 <= 1'b0;
            last_ch_d2  <= 1'b0;
        end else begin
            first_ch_d2 <= first_ch_d1;
            last_ch_d2  <= last_ch_d1;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 4: Channel Accumulator (M_accum = sum U .* V)
    // Latency: 1 cycle
    // -------------------------------------------------------------------------
    logic                          accum_valid;
    logic signed [ACCUM_WIDTH-1:0] m_accum [0:3][0:3];

    channel_accumulator #(
        .IN_WIDTH(PROD_WIDTH),
        .OUT_WIDTH(ACCUM_WIDTH),
        .MAX_CHANNELS(MAX_CHANNELS)
    ) u_channel_accum (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(mult_valid),
        .first_channel(first_ch_d2),
        .last_channel(last_ch_d2),
        .m_in(m_matrix),
        .valid_out(accum_valid),
        .m_accum_out(m_accum)
    );

    // -------------------------------------------------------------------------
    // Stage 5 & 6: Output Transform Unit (Y = A^T * M * A)
    // Latency: 2 cycles (1 cycle for col, 1 cycle for row + saturation)
    // -------------------------------------------------------------------------
    output_transform_2d #(
        .IN_WIDTH(ACCUM_WIDTH),
        .INTER_WIDTH(ACCUM_WIDTH + 2),
        .FINAL_WIDTH(ACCUM_WIDTH + 4),
        .OUT_WIDTH(DATA_OUT_WIDTH),
        .SHIFT_BITS(SHIFT_BITS)
    ) u_output_trans (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(accum_valid),
        .m_in(m_accum),
        .valid_out(out_valid),
        .y_out(y_tile)
    );

endmodule
