// =============================================================================
// Module: direct_conv_top
// Description: Conventional Direct 3x3 Spatial Convolution Engine (Baseline)
// Generates 2x2 output tile using 4 concurrent 3x3 dot products.
// Each 3x3 dot product requires 9 multiplications.
// Total DSP Multipliers = 4 * 9 = 36 multiplications per tile.
// Used as the fair comparison baseline for Winograd F(2x2, 3x3).
// =============================================================================
`timescale 1ns / 1ps

module direct_conv_top #(
    parameter DATA_IN_WIDTH  = 16,
    parameter WEIGHT_WIDTH   = 16,
    parameter PROD_WIDTH     = 32,
    parameter ACCUM_WIDTH    = 36,
    parameter DATA_OUT_WIDTH = 16,
    parameter SHIFT_BITS     = 6
)(
    input  logic                            clk,
    input  logic                            rst_n,

    input  logic                            in_valid,
    output logic                            in_ready,
    input  logic signed [DATA_IN_WIDTH-1:0] d_tile [0:3][0:3], // 4x4 input feature tile
    input  logic signed [WEIGHT_WIDTH-1:0]  w_kernel [0:2][0:2], // 3x3 spatial weight kernel
    input  logic                            first_ch,
    input  logic                            last_ch,

    output logic                            out_valid,
    output logic signed [DATA_OUT_WIDTH-1:0] y_tile [0:1][0:1]
);

    assign in_ready = 1'b1;

    // Stage 1: 36 multiplications (9 multiplications per each of the 4 output pixels)
    // Sub-window 0,0: d[0..2][0..2] * w[0..2][0..2]
    // Sub-window 0,1: d[0..2][1..3] * w[0..2][0..2]
    // Sub-window 1,0: d[1..3][0..2] * w[0..2][0..2]
    // Sub-window 1,1: d[1..3][1..3] * w[0..2][0..2]

    logic signed [ACCUM_WIDTH-1:0] dot_prod [0:1][0:1];
    logic                          mult_valid;
    logic                          first_ch_d1, last_ch_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_valid  <= 1'b0;
            first_ch_d1 <= 1'b0;
            last_ch_d1  <= 1'b0;
            for (int r = 0; r < 2; r = r + 1) begin
                for (int c = 0; c < 2; c = c + 1) begin
                    dot_prod[r][c] <= '0;
                end
            end
        end else begin
            mult_valid  <= in_valid;
            first_ch_d1 <= first_ch;
            last_ch_d1  <= last_ch;

            if (in_valid) begin
                for (int r = 0; r < 2; r = r + 1) begin
                    for (int c = 0; c < 2; c = c + 1) begin
                        logic signed [ACCUM_WIDTH-1:0] sum_p;
                        sum_p = '0;
                        for (int kr = 0; kr < 3; kr = kr + 1) begin
                            for (int kc = 0; kc < 3; kc = kc + 1) begin
                                sum_p = sum_p + (d_tile[r + kr][c + kc] * w_kernel[kr][kc]);
                            end
                        end
                        dot_prod[r][c] <= sum_p;
                    end
                end
            end
        end
    end

    // Stage 2: Channel Accumulator
    logic signed [ACCUM_WIDTH-1:0] ch_accum [0:1][0:1];
    logic                          accum_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_valid <= 1'b0;
            for (int r = 0; r < 2; r = r + 1) begin
                for (int c = 0; c < 2; c = c + 1) begin
                    ch_accum[r][c] <= '0;
                end
            end
        end else begin
            if (mult_valid) begin
                for (int r = 0; r < 2; r = r + 1) begin
                    for (int c = 0; c < 2; c = c + 1) begin
                        if (first_ch_d1) begin
                            ch_accum[r][c] <= dot_prod[r][c];
                        end else begin
                            ch_accum[r][c] <= ch_accum[r][c] + dot_prod[r][c];
                        end
                    end
                end
                accum_valid <= last_ch_d1;
            end else begin
                accum_valid <= 1'b0;
            end
        end
    end

    // Stage 3: Requantization and Saturation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            for (int r = 0; r < 2; r = r + 1) begin
                for (int c = 0; c < 2; c = c + 1) begin
                    y_tile[r][c] <= '0;
                end
            end
        end else begin
            out_valid <= accum_valid;
            if (accum_valid) begin
                for (int r = 0; r < 2; r = r + 1) begin
                    for (int c = 0; c < 2; c = c + 1) begin
                        logic signed [ACCUM_WIDTH-1:0] shifted;
                        shifted = (ch_accum[r][c] + (1 << (SHIFT_BITS - 1))) >>> SHIFT_BITS;
                        if (shifted > 32767) begin
                            y_tile[r][c] <= 16'sh7FFF;
                        end else if (shifted < -32768) begin
                            y_tile[r][c] <= 16'sh8000;
                        end else begin
                            y_tile[r][c] <= shifted[DATA_OUT_WIDTH-1:0];
                        end
                    end
                end
            end
        end
    end

endmodule
