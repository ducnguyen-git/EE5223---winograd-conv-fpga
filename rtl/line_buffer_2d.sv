`timescale 1ns / 1ps
// Three retained rows per channel plus horizontal windows; no full-frame storage.
module line_buffer_2d #(
    parameter IMAGE_WIDTH = 8,
    parameter IMAGE_HEIGHT = 8,
    parameter CHANNELS = 1,
    parameter DATA_WIDTH = 16
)(
    input logic clk, rst_n, start,
    input logic pixel_valid,
    output logic pixel_ready,
    input logic signed [DATA_WIDTH-1:0] pixel_data,
    output logic tile_valid,
    input logic tile_ready,
    output logic signed [DATA_WIDTH-1:0] tile [0:3][0:3],
    output int unsigned tile_channel,
    output logic frame_done
);
    initial begin
        if (IMAGE_WIDTH < 4 || IMAGE_HEIGHT < 4 || CHANNELS < 1 || DATA_WIDTH < 1)
            $fatal(1, "Invalid line buffer dimensions");
    end
    logic running;
    int unsigned row, col, channel;
    // shortcut: asynchronous row reads; pipeline reads when targeting synchronous RAM.
    logic signed [DATA_WIDTH-1:0] rows [0:2][0:CHANNELS-1][0:IMAGE_WIDTH-1];
    logic signed [DATA_WIDTH-1:0] window [0:CHANNELS-1][0:3][0:3];
    logic signed [DATA_WIDTH-1:0] column [0:3];
    assign column[0] = rows[2][channel][col];
    assign column[1] = rows[1][channel][col];
    assign column[2] = rows[0][channel][col];
    assign column[3] = pixel_data;
    assign pixel_ready = running && (!tile_valid || tile_ready);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 0;
            row <= 0;
            col <= 0;
            channel <= 0;
            tile_valid <= 0;
            tile_channel <= 0;
            frame_done <= 0;
        end else begin
            frame_done <= 0;
            if (tile_valid && tile_ready) tile_valid <= 0;
            if (start) begin
                running <= 1;
                row <= 0;
                col <= 0;
                channel <= 0;
                tile_valid <= 0;
            end else if (pixel_valid && pixel_ready) begin
                rows[2][channel][col] <= rows[1][channel][col];
                rows[1][channel][col] <= rows[0][channel][col];
                rows[0][channel][col] <= pixel_data;
                for (int r=0; r<4; r++) begin
                    for (int c=0; c<3; c++)
                        window[channel][r][c] <= window[channel][r][c+1];
                    window[channel][r][3] <= column[r];
                end
                if (row >= 3 && col >= 3 && row[0] && col[0]) begin
                    for (int r=0; r<4; r++) begin
                        for (int c=0; c<3; c++) tile[r][c] <= window[channel][r][c+1];
                        tile[r][3] <= column[r];
                    end
                    tile_channel <= channel;
                    tile_valid <= 1;
                end
                if (channel == CHANNELS-1) begin
                    channel <= 0;
                    if (col == IMAGE_WIDTH-1) begin
                        col <= 0;
                        if (row == IMAGE_HEIGHT-1) begin
                            row <= 0;
                            running <= 0;
                            frame_done <= 1;
                        end else row <= row + 1;
                    end else col <= col + 1;
                end else channel <= channel + 1;
            end
        end
    end
endmodule
