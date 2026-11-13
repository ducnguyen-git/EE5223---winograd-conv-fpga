`timescale 1ns / 1ps
module stream_top_tb;
    parameter IMAGE_WIDTH = 7;
    parameter IMAGE_HEIGHT = 7;
    parameter CHANNELS = 3;
    parameter FILTERS = 3;
    localparam TILE_COLS = (IMAGE_WIDTH-2)/2;
    localparam TILE_ROWS = (IMAGE_HEIGHT-2)/2;
    localparam OUTPUTS = TILE_COLS*TILE_ROWS*FILTERS;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, weight_valid = 0, weight_ready, start = 0, start_ready;
    logic pixel_valid = 0, pixel_ready, out_valid, frame_done;
    int unsigned weight_filter = 0, weight_channel = 0, out_filter, out_row, out_col;
    logic signed [15:0] weight_tile [0:3][0:3], pixel_data;
    logic signed [15:0] y_tile [0:1][0:1];
    int frame_id = 0, checked = 0, completed = 0, transforms = 0, pixels = 0, stalls = 0;
    integer g2 [0:3][0:2] = '{'{2,0,0}, '{1,1,1}, '{1,-1,1}, '{0,0,2}};

    winograd_stream_top #(.IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
                          .CHANNELS(CHANNELS), .FILTERS(FILTERS)) dut (.*);

    function automatic integer pixel(input int frame, row, col, channel);
        return ((frame*31 + row*17 + col*11 + channel*7) % 127)-63;
    endfunction
    function automatic integer kernel(input int filter_id, channel, row, col);
        return ((filter_id*2 + channel*5 + row*3 + col) % 7)-3;
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            checked = 0;
            completed = 0;
            transforms = 0;
            pixels = 0;
            stalls = 0;
        end else begin
            if (dut.u_core.u_input_trans.valid_in) transforms++;
            if (pixel_valid && pixel_ready) pixels++;
            if (pixel_valid && !pixel_ready) stalls++;
            if (frame_done) completed++;
            if (out_valid) begin
                if (out_filter != checked % FILTERS ||
                    out_col != ((checked/FILTERS) % TILE_COLS)*2 ||
                    out_row != ((checked/FILTERS) / TILE_COLS)*2)
                    $fatal(1, "Wrong output order/coordinates");
                for (int r=0; r<2; r++) begin
                    for (int c=0; c<2; c++) begin
                        integer expected_value;
                        expected_value = 0;
                        for (int ch=0; ch<CHANNELS; ch++)
                            for (int kr=0; kr<3; kr++)
                                for (int kc=0; kc<3; kc++)
                                    expected_value += pixel(frame_id, int'(out_row)+r+kr,
                                        int'(out_col)+c+kc, ch)*kernel(int'(out_filter), ch, kr, kc);
                        if (y_tile[r][c] !== 16'(expected_value))
                            $fatal(1, "Frame %0d tile %0d [%0d,%0d]: got %0d expected %0d",
                                   frame_id, checked, r, c, y_tile[r][c], expected_value);
                    end
                end
                checked++;
            end
        end
    end

    task automatic load_weights;
        for (int f=0; f<FILTERS; f++) begin
            for (int ch=0; ch<CHANNELS; ch++) begin
                weight_filter = f;
                weight_channel = ch;
                for (int r=0; r<4; r++) begin
                    for (int c=0; c<4; c++) begin
                        integer value;
                        value = 0;
                        // U*64 = 16 * (2G) g (2G)^T, exact for integer kernels.
                        for (int a=0; a<3; a++)
                            for (int b=0; b<3; b++) value += 16*g2[r][a]*kernel(f,ch,a,b)*g2[c][b];
                        weight_tile[r][c] = 16'(value);
                    end
                end
                weight_valid = 1;
                do @(posedge clk); while (!weight_ready);
                @(negedge clk);
                weight_valid = 0;
            end
        end
    endtask
    task automatic begin_image;
        start = 1;
        do @(posedge clk); while (!start_ready);
        @(negedge clk);
        start = 0;
        if (weight_ready) $fatal(1, "Weights writable during a frame");
    endtask
    task automatic send_pixel(input integer value);
        pixel_data = 16'(value);
        pixel_valid = 1;
        do @(posedge clk); while (!pixel_ready);
        @(negedge clk);
        pixel_valid = 0;
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        if (start_ready || pixel_ready) $fatal(1, "Accepted uninitialized frame");
        weight_filter = FILTERS;
        weight_valid = 1;
        @(negedge clk);
        if (weight_ready) $fatal(1, "Accepted invalid weight address");
        weight_valid = 0;
        load_weights();
        begin_image();
        send_pixel(100);
        send_pixel(-100);
        // Reset must invalidate weights, row history, and the in-flight frame.
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        if (start_ready || pixel_ready) $fatal(1, "Reset retained a valid frame/weights");
        load_weights();
        for (int frame=0; frame<2; frame++) begin
            frame_id = frame;
            checked = 0;
            begin_image();
            // Attempt a write while processing; stored weights must remain unchanged.
            weight_filter = 0;
            weight_channel = 0;
            weight_valid = 1;
            for (int r=0; r<4; r++)
                for (int c=0; c<4; c++) weight_tile[r][c] = 30000;
            for (int row=0; row<IMAGE_HEIGHT; row++) begin
                for (int col=0; col<IMAGE_WIDTH; col++) begin
                    for (int ch=0; ch<CHANNELS; ch++) begin
                        if ((row+col+ch+frame) % 5 == 1) repeat (2) @(negedge clk);
                        send_pixel(pixel(frame, row, col, ch));
                    end
                end
            end
            pixel_valid = 0;
            weight_valid = 0;
            while (completed != frame+1) @(negedge clk);
            if (checked != OUTPUTS) $fatal(1, "Missing outputs");
        end
        if (pixels != 2*IMAGE_WIDTH*IMAGE_HEIGHT*CHANNELS ||
            transforms != 2*TILE_COLS*TILE_ROWS*CHANNELS)
            $fatal(1, "Pixels/transforms were not reused: %0d / %0d", pixels, transforms);
        if (FILTERS > 1 && stalls == 0) $fatal(1, "Backpressure not exercised");
        repeat (8) @(negedge clk);
        if (checked != OUTPUTS || completed != 2) $fatal(1, "Unexpected extra output/frame");
        $display("PASS: streamed %0dx%0d x %0d channels, %0d filters, two frames with stored weights",
                 IMAGE_WIDTH, IMAGE_HEIGHT, CHANNELS, FILTERS);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Streaming watchdog timeout");
    end
endmodule
