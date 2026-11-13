// =============================================================================
// Module: multiplier_array
// Description: Parameterizable Winograd element-wise multiplier engine
// Computes M = U .* V (16 products)
// Only PARALLEL_DSPS=16 is supported (all products computed in one cycle).
// =============================================================================
`timescale 1ns / 1ps

module multiplier_array #(
    parameter V_WIDTH       = 18,
    parameter U_WIDTH       = 16,
    parameter PROD_WIDTH    = 34,
    parameter PARALLEL_DSPS = 16
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic signed [V_WIDTH-1:0]     v_in [0:3][0:3],
    input  logic signed [U_WIDTH-1:0]     u_in [0:3][0:3],

    output logic                          valid_out,
    output logic signed [PROD_WIDTH-1:0]  m_out [0:3][0:3]
);

    initial begin
        if (PARALLEL_DSPS != 16)
            $fatal(1, "multiplier_array supports only PARALLEL_DSPS=16");
    end

    // All 16 element-wise multipliers in parallel (1 pipeline stage).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int r = 0; r < 4; r = r + 1) begin
                for (int c = 0; c < 4; c = c + 1) begin
                    m_out[r][c] <= '0;
                end
            end
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                for (int r = 0; r < 4; r = r + 1) begin
                    for (int c = 0; c < 4; c = c + 1) begin
                        m_out[r][c] <= v_in[r][c] * u_in[r][c];
                    end
                end
            end
        end
    end

endmodule
