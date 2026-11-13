// =============================================================================
// Module: output_transform_2d
// Description: Multiplierless 2D Winograd output transform: Y = A^T * M * A
// Input:  4x4 intermediate accumulated products (signed 36-bit)
// Output: 2x2 final output tile (signed 16-bit saturated/requantized)
// =============================================================================
`timescale 1ns / 1ps

module output_transform_2d #(
    parameter IN_WIDTH    = 36,
    parameter INTER_WIDTH = IN_WIDTH + 2,
    parameter FINAL_WIDTH = INTER_WIDTH + 2,
    parameter OUT_WIDTH   = 16,
    parameter SHIFT_BITS  = 6
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic signed [IN_WIDTH-1:0]    m_in [0:3][0:3], // [row][col]

    output logic                          valid_out,
    output logic signed [OUT_WIDTH-1:0]   y_out [0:1][0:1]  // [row][col]
);

    initial begin
        if (IN_WIDTH < 1 || INTER_WIDTH < IN_WIDTH + 2 ||
            FINAL_WIDTH < INTER_WIDTH + 2 || OUT_WIDTH < 1 ||
            OUT_WIDTH > FINAL_WIDTH || SHIFT_BITS < 0 || SHIFT_BITS > FINAL_WIDTH)
            $fatal(1, "Invalid output transform widths or shift");
    end

    localparam logic signed [OUT_WIDTH-1:0] OUT_MAX = {1'b0, {(OUT_WIDTH-1){1'b1}}};
    localparam logic signed [OUT_WIDTH-1:0] OUT_MIN = {1'b1, {(OUT_WIDTH-1){1'b0}}};
    // One guard bit keeps the rounding addition from overflowing.
    localparam logic signed [FINAL_WIDTH:0] ROUND_BIAS =
        (SHIFT_BITS > 0) ? ({{FINAL_WIDTH{1'b0}}, 1'b1} << (SHIFT_BITS - 1)) : '0;

    // Step 1: Column transform on 4 columns -> 2x4 intermediate matrix
    logic signed [INTER_WIDTH-1:0] col_res [0:1][0:3];

    genvar c;
    generate
        for (c = 0; c < 4; c = c + 1) begin : gen_col_out
            logic signed [IN_WIDTH-1:0] col_in [0:3];
            assign col_in[0] = m_in[0][c];
            assign col_in[1] = m_in[1][c];
            assign col_in[2] = m_in[2][c];
            assign col_in[3] = m_in[3][c];

            logic signed [INTER_WIDTH-1:0] col_out [0:1];
            output_transform_1d #(
                .IN_WIDTH(IN_WIDTH),
                .OUT_WIDTH(INTER_WIDTH)
            ) u_col_trans (
                .m(col_in),
                .y(col_out)
            );

            assign col_res[0][c] = col_out[0];
            assign col_res[1][c] = col_out[1];
        end
    endgenerate

    // Pipeline register between column and row transform
    logic signed [INTER_WIDTH-1:0] col_reg [0:1][0:3];
    logic                          valid_stage1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_stage1 <= 1'b0;
            for (int r = 0; r < 2; r = r + 1) begin
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

    // Step 2: Row transform on 2 rows -> 2x2 matrix
    logic signed [FINAL_WIDTH-1:0] row_res [0:1][0:1];

    genvar r;
    generate
        for (r = 0; r < 2; r = r + 1) begin : gen_row_out
            logic signed [INTER_WIDTH-1:0] row_in [0:3];
            assign row_in[0] = col_reg[r][0];
            assign row_in[1] = col_reg[r][1];
            assign row_in[2] = col_reg[r][2];
            assign row_in[3] = col_reg[r][3];

            logic signed [FINAL_WIDTH-1:0] row_out [0:1];
            output_transform_1d #(
                .IN_WIDTH(INTER_WIDTH),
                .OUT_WIDTH(FINAL_WIDTH)
            ) u_row_trans (
                .m(row_in),
                .y(row_out)
            );

            assign row_res[r][0] = row_out[0];
            assign row_res[r][1] = row_out[1];
        end
    endgenerate

    // Stage 3: Requantization (shift with rounding) and Saturation
    logic signed [FINAL_WIDTH:0] shifted [0:1][0:1];
    logic signed [OUT_WIDTH-1:0]   clamped [0:1][0:1];

    always_comb begin
        for (int i = 0; i < 2; i = i + 1) begin
            for (int j = 0; j < 2; j = j + 1) begin
                shifted[i][j] = ($signed({row_res[i][j][FINAL_WIDTH-1], row_res[i][j]}) + ROUND_BIAS) >>> SHIFT_BITS;
                
                // Clamp to the configured signed output range.
                if (shifted[i][j] > $signed({{(FINAL_WIDTH+1-OUT_WIDTH){OUT_MAX[OUT_WIDTH-1]}}, OUT_MAX})) begin
                    clamped[i][j] = OUT_MAX;
                end else if (shifted[i][j] < $signed({{(FINAL_WIDTH+1-OUT_WIDTH){OUT_MIN[OUT_WIDTH-1]}}, OUT_MIN})) begin
                    clamped[i][j] = OUT_MIN;
                end else begin
                    clamped[i][j] = shifted[i][j][OUT_WIDTH-1:0];
                end
            end
        end
    end

    // Output registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int i = 0; i < 2; i = i + 1) begin
                for (int j = 0; j < 2; j = j + 1) begin
                    y_out[i][j] <= '0;
                end
            end
        end else begin
            valid_out <= valid_stage1;
            if (valid_stage1) begin
                y_out <= clamped;
            end
        end
    end

endmodule
