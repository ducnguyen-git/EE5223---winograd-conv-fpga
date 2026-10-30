// =============================================================================
// Module: input_transform_2d
// Description: Multiplierless 2D Winograd input transform: V = B^T * d * B
// Pipelined architecture with intermediate registers between 1D column and 1D row transforms
// Input:  16x signed 16-bit
// Output: 16x signed 18-bit
// Latency: 1 clock cycle (pipelined)
// =============================================================================
`timescale 1ns / 1ps

module input_transform_2d #(
    parameter DATA_IN_WIDTH  = 16,
    parameter INTER_WIDTH    = 17,
    parameter DATA_OUT_WIDTH = 18
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic signed [DATA_IN_WIDTH-1:0]  d_in [0:3][0:3], // [row][col]

    output logic                          valid_out,
    output logic signed [DATA_OUT_WIDTH-1:0] v_out [0:3][0:3]
);

    // Step 1: Column transform (combinational)
    logic signed [INTER_WIDTH-1:0] col_res [0:3][0:3];

    genvar c;
    generate
        for (c = 0; c < 4; c = c + 1) begin : gen_col_transform
            logic signed [DATA_IN_WIDTH-1:0] col_in [0:3];
            assign col_in[0] = d_in[0][c];
            assign col_in[1] = d_in[1][c];
            assign col_in[2] = d_in[2][c];
            assign col_in[3] = d_in[3][c];

            logic signed [INTER_WIDTH-1:0] col_out [0:3];
            input_transform_1d #(
                .DATA_WIDTH(DATA_IN_WIDTH),
                .OUT_WIDTH(INTER_WIDTH)
            ) u_trans_col (
                .d(col_in),
                .v(col_out)
            );

            assign col_res[0][c] = col_out[0];
            assign col_res[1][c] = col_out[1];
            assign col_res[2][c] = col_out[2];
            assign col_res[3][c] = col_out[3];
        end
    endgenerate

    // Pipeline register between column and row transform
    logic signed [INTER_WIDTH-1:0] col_reg [0:3][0:3];
    logic                          valid_stage1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_stage1 <= 1'b0;
            for (int r = 0; r < 4; r = r + 1) begin
                for (int c_idx = 0; c_idx < 4; c_idx = c_idx + 1) begin
                    col_reg[r][c_idx] <= '0;
                end
            end
        end else begin
            valid_stage1 <= valid_in;
            if (valid_in) begin
                col_reg <= col_res;
            end
        end
    end

    // Step 2: Row transform
    genvar r;
    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_row_transform
            logic signed [INTER_WIDTH-1:0] row_in [0:3];
            assign row_in[0] = col_reg[r][0];
            assign row_in[1] = col_reg[r][1];
            assign row_in[2] = col_reg[r][2];
            assign row_in[3] = col_reg[r][3];

            logic signed [DATA_OUT_WIDTH-1:0] row_out [0:3];
            input_transform_1d #(
                .DATA_WIDTH(INTER_WIDTH),
                .OUT_WIDTH(DATA_OUT_WIDTH)
            ) u_trans_row (
                .d(row_in),
                .v(row_out)
            );

            assign v_out[r][0] = row_out[0];
            assign v_out[r][1] = row_out[1];
            assign v_out[r][2] = row_out[2];
            assign v_out[r][3] = row_out[3];
        end
    endgenerate

    assign valid_out = valid_stage1;

endmodule
