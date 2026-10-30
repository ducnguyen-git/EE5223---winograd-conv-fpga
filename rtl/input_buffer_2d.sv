// =============================================================================
// Module: input_buffer_2d
// Description: Streams 16-bit input values or receives burst tile into 4x4 matrix
// =============================================================================
`timescale 1ns / 1ps

module input_buffer_2d #(
    parameter DATA_WIDTH = 16
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start_tile,
    input  logic                          data_valid,
    input  logic signed [DATA_WIDTH-1:0]  data_in [0:3][0:3],

    output logic                          tile_ready,
    output logic signed [DATA_WIDTH-1:0]  tile_out [0:3][0:3]
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_ready <= 1'b0;
            for (int r = 0; r < 4; r = r + 1) begin
                for (int c = 0; c < 4; c = c + 1) begin
                    tile_out[r][c] <= '0;
                end
            end
        end else begin
            if (data_valid) begin
                tile_out   <= data_in;
                tile_ready <= 1'b1;
            end else begin
                tile_ready <= 1'b0;
            end
        end
    end

endmodule
