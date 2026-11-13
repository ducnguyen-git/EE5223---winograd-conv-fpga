`timescale 1ns / 1ps
module line_buffer_tb;
    localparam W = 6, H = 6, C = 2;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, start = 0, pixel_valid = 0, pixel_ready;
    logic signed [15:0] pixel_data;
    logic tile_valid, tile_ready, frame_done;
    logic signed [15:0] tile [0:3][0:3], held_tile [0:3][0:3];
    int unsigned tile_channel, held_channel;
    int cycles = 0, checked = 0;
    logic held = 0, finished = 0;
    line_buffer_2d #(.IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .CHANNELS(C)) dut (.*);
    always @(negedge clk) cycles++;
    assign tile_ready = cycles % 9 >= 5;
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_done) finished = 1;
            if (held && (!tile_valid || tile_channel != held_channel || tile !== held_tile))
                $fatal(1, "Line-buffer output changed under backpressure");
            held = tile_valid && !tile_ready;
            held_tile = tile;
            held_channel = tile_channel;
            if (tile_valid && tile_ready) begin
                integer top_row, left_col, channel;
                channel = checked % C;
                top_row = ((checked/C)/2)*2;
                left_col = ((checked/C)%2)*2;
                if (tile_channel != channel) $fatal(1, "Wrong tile channel");
                for (int r=0; r<4; r++)
                    for (int c=0; c<4; c++)
                        if (tile[r][c] !== 16'((((top_row+r)*W+left_col+c)*C+channel)-100))
                            $fatal(1, "Wrong window %0d [%0d,%0d]", checked, r, c);
                checked++;
            end
        end
    end
    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        start = 1;
        @(negedge clk);
        start = 0;
        for (int i=0; i<W*H*C; i++) begin
            if (i % 5 == 0) repeat (2) @(negedge clk);
            pixel_data = 16'(i-100);
            pixel_valid = 1;
            do @(posedge clk); while (!pixel_ready);
            @(negedge clk);
            pixel_valid = 0;
        end
        while (checked != 8 || !finished) @(negedge clk);
        repeat (10) @(negedge clk);
        if (checked != 8 || pixel_ready) $fatal(1, "Frame did not stop cleanly");
        $display("PASS: overlapping line-buffer windows and stalled output stability");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "Line-buffer watchdog timeout");
    end
endmodule
