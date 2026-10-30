// =============================================================================
// Module: channel_accumulator
// Description: Multi-channel partial sum accumulator in the Winograd domain
// Accumulates 16 product elements across Cin channels before output transform:
//   M_accum = sum_{c=1}^{Cin} (U_c .* V_c)
// Input:  signed 34-bit products
// Output: signed 36-bit accumulated matrix
// =============================================================================
`timescale 1ns / 1ps

module channel_accumulator #(
    parameter IN_WIDTH  = 34,
    parameter OUT_WIDTH = 36
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic                          first_channel,
    input  logic                          last_channel,
    input  logic signed [IN_WIDTH-1:0]    m_in [0:3][0:3],

    output logic                          valid_out,
    output logic signed [OUT_WIDTH-1:0]   m_accum_out [0:3][0:3]
);

    logic signed [OUT_WIDTH-1:0] accum_reg [0:3][0:3];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int r = 0; r < 4; r = r + 1) begin
                for (int c = 0; c < 4; c = c + 1) begin
                    accum_reg[r][c]   <= '0;
                    m_accum_out[r][c] <= '0;
                end
            end
        end else begin
            if (valid_in) begin
                for (int r = 0; r < 4; r = r + 1) begin
                    for (int c = 0; c < 4; c = c + 1) begin
                        logic signed [OUT_WIDTH-1:0] cur_sum;
                        logic signed [OUT_WIDTH-1:0] sign_ext_in;
                        sign_ext_in = $signed({{ (OUT_WIDTH-IN_WIDTH){m_in[r][c][IN_WIDTH-1]} }, m_in[r][c]});

                        if (first_channel) begin
                            cur_sum = sign_ext_in;
                        end else begin
                            cur_sum = accum_reg[r][c] + sign_ext_in;
                        end

                        accum_reg[r][c] <= cur_sum;

                        if (last_channel) begin
                            m_accum_out[r][c] <= cur_sum;
                        end
                    end
                end
                valid_out <= last_channel;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
