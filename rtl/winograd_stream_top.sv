`timescale 1ns / 1ps
// Raster pixels (row, column, input channel) -> spatial tiles -> output filters.
module winograd_stream_top #(
    parameter IMAGE_WIDTH = 8,
    parameter IMAGE_HEIGHT = 8,
    parameter CHANNELS = 1,
    parameter FILTERS = 1,
    parameter DATA_IN_WIDTH = 16,
    parameter U_WIDTH = 16,
    parameter DATA_OUT_WIDTH = 16,
    parameter SHIFT_BITS = 6
)(
    input logic clk, rst_n,
    input logic weight_valid,
    output logic weight_ready,
    input int unsigned weight_filter, weight_channel,
    input logic signed [U_WIDTH-1:0] weight_tile [0:3][0:3],
    input logic start,
    output logic start_ready,
    input logic pixel_valid,
    output logic pixel_ready,
    input logic signed [DATA_IN_WIDTH-1:0] pixel_data,
    output logic out_valid,
    output logic signed [DATA_OUT_WIDTH-1:0] y_tile [0:1][0:1],
    output int unsigned out_filter, out_row, out_col,
    output logic frame_done
);
    // shortcut: emit complete 2x2 tiles; add border masking for odd output dimensions.
    localparam TILE_COLS = (IMAGE_WIDTH-2)/2;
    localparam TILE_ROWS = (IMAGE_HEIGHT-2)/2;
    localparam OUTPUTS = TILE_COLS*TILE_ROWS*FILTERS;
    initial begin
        if (CHANNELS < 1 || FILTERS < 1 || IMAGE_WIDTH < 4 || IMAGE_HEIGHT < 4)
            $fatal(1, "Invalid streaming convolution dimensions");
    end

    logic active, all_weights, pixels_done, begin_frame, line_done;
    logic loaded [0:FILTERS-1][0:CHANNELS-1];
    // shortcut: asynchronous weight reads; add a read stage for synchronous RAM.
    logic signed [U_WIDTH-1:0] weights [0:FILTERS-1][0:CHANNELS-1][0:3][0:3];
    int unsigned filter_index, replay_channel, outputs_sent;
    int unsigned tile_channel, selected_channel;
    logic tile_valid, tile_ready, line_pixel_ready, core_valid, core_ready;
    logic first_channel, last_channel;
    logic signed [DATA_IN_WIDTH-1:0] tile [0:3][0:3];
    logic signed [U_WIDTH-1:0] selected_weights [0:3][0:3];

    always_comb begin
        all_weights = 1;
        for (int f=0; f<FILTERS; f++)
            for (int c=0; c<CHANNELS; c++) all_weights &= loaded[f][c];
    end
    assign weight_ready = !active && weight_filter < FILTERS && weight_channel < CHANNELS;
    assign start_ready = !active && all_weights;
    assign begin_frame = start && start_ready;
    assign pixel_ready = active && filter_index == 0 && line_pixel_ready;
    assign tile_ready = active && filter_index == 0 && core_ready;
    assign selected_channel = (filter_index == 0) ? tile_channel : replay_channel;
    assign selected_weights = weights[filter_index][selected_channel];
    assign first_channel = selected_channel == 0;
    assign last_channel = selected_channel == CHANNELS-1;
    assign core_valid = active && ((filter_index == 0) ? tile_valid : 1'b1);
    assign out_filter = outputs_sent % FILTERS;
    assign out_col = ((outputs_sent / FILTERS) % TILE_COLS)*2;
    assign out_row = ((outputs_sent / FILTERS) / TILE_COLS)*2;

    line_buffer_2d #(.IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
                     .CHANNELS(CHANNELS), .DATA_WIDTH(DATA_IN_WIDTH)) u_lines (
        .clk(clk), .rst_n(rst_n), .start(begin_frame),
        .pixel_valid(pixel_valid && active && filter_index == 0),
        .pixel_ready(line_pixel_ready), .pixel_data(pixel_data),
        .tile_valid(tile_valid), .tile_ready(tile_ready), .tile(tile),
        .tile_channel(tile_channel), .frame_done(line_done));

    winograd_top #(.MAX_CHANNELS(CHANNELS), .DATA_IN_WIDTH(DATA_IN_WIDTH),
                   .U_WIDTH(U_WIDTH), .DATA_OUT_WIDTH(DATA_OUT_WIDTH),
                   .SHIFT_BITS(SHIFT_BITS)) u_core (
        .clk(clk), .rst_n(rst_n), .in_valid(core_valid), .in_ready(core_ready),
        .d_tile(tile), .u_tile(selected_weights),
        .first_ch(first_channel), .last_ch(last_channel),
        .reuse_input(filter_index != 0), .out_valid(out_valid), .y_tile(y_tile));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 0;
            pixels_done <= 0;
            filter_index <= 0;
            replay_channel <= 0;
            outputs_sent <= 0;
            frame_done <= 0;
            for (int f=0; f<FILTERS; f++)
                for (int c=0; c<CHANNELS; c++) loaded[f][c] <= 0;
        end else begin
            frame_done <= 0;
            if (weight_valid && weight_ready) begin
                weights[weight_filter][weight_channel] <= weight_tile;
                loaded[weight_filter][weight_channel] <= 1;
            end
            if (begin_frame) begin
                active <= 1;
                pixels_done <= 0;
                outputs_sent <= 0;
                filter_index <= 0;
                replay_channel <= 0;
            end else begin
                if (line_done) pixels_done <= 1;
                if (core_valid && core_ready) begin
                    if (last_channel) begin
                        replay_channel <= 0;
                        filter_index <= (filter_index == FILTERS-1) ? 0 : filter_index+1;
                    end else if (filter_index != 0) replay_channel <= replay_channel+1;
                end
                if (out_valid) outputs_sent <= outputs_sent+1;
                if (active && (pixels_done || line_done) &&
                    (outputs_sent == OUTPUTS || (out_valid && outputs_sent == OUTPUTS-1))) begin
                    active <= 0;
                    frame_done <= 1;
                end
            end
        end
    end
endmodule
