`timescale 1ns / 1ps
module input_reuse_tb;
    parameter CACHE_CHANNELS = 64;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, valid = 0, reuse_input = 0, first_ch = 0, last_ch = 0;
    logic ready, reference_ready, out_valid, reference_valid;
    logic signed [15:0] d [0:3][0:3], original_d [0:3][0:3], u [0:3][0:3];
    logic signed [15:0] y [0:1][0:1], reference_y [0:1][0:1];
    integer outputs = 0, transforms = 0, reference_transforms = 0;
    winograd_top #(.MAX_CHANNELS(CACHE_CHANNELS)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(valid), .in_ready(ready),
        .d_tile(d), .u_tile(u), .first_ch(first_ch), .last_ch(last_ch),
        .reuse_input(reuse_input), .out_valid(out_valid), .y_tile(y));
    winograd_top #(.MAX_CHANNELS(CACHE_CHANNELS)) reference_dut (
        .clk(clk), .rst_n(rst_n), .in_valid(valid && ready), .in_ready(reference_ready),
        .d_tile(original_d), .u_tile(u), .first_ch(first_ch), .last_ch(last_ch),
        .reuse_input(1'b0), .out_valid(reference_valid), .y_tile(reference_y));

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_input_trans.valid_in) transforms++;
            if (reference_dut.u_input_trans.valid_in) reference_transforms++;
            if (reuse_input && dut.u_input_trans.valid_in)
                $fatal(1, "Replay recomputed the input transform");
        end
    end
    always @(negedge clk) begin
        if (rst_n) begin
            if (out_valid !== reference_valid) $fatal(1, "Replay changed output timing/count");
            if (out_valid) begin
                for (int r=0; r<2; r++)
                    for (int c=0; c<2; c++)
                        if (y[r][c] !== reference_y[r][c])
                            $fatal(1, "Replay mismatch at output %0d [%0d,%0d]", outputs, r, c);
                outputs++;
            end
        end
    end

    task automatic send_channel(input int tile, input int filter_id, input int channel,
                                input int channels, input bit replay);
        reuse_input = replay;
        first_ch = (channel == 0);
        last_ch = (channel == channels-1);
        for (int r=0; r<4; r++) begin
            for (int c=0; c<4; c++) begin
                original_d[r][c] = 16'(((tile*23 + channel*17 + r*11 + c*7) % 127)-63);
                // Replay must ignore changed input data, not silently transform it.
                d[r][c] = replay ? 16'sd30000 : original_d[r][c];
                u[r][c] = 16'(((filter_id*31 + channel*13 + r*5 + c*19) % 97)-48);
            end
        end
        valid = 1;
        do @(posedge clk); while (!ready);
        @(negedge clk);
        valid = 0;
    endtask
    task automatic send_filter(input int tile, input int filter_id, input int channels,
                               input bit replay, input bit gaps);
        for (int ch=0; ch<channels; ch++) begin
            if (gaps && ch % 3 == 1) begin
                valid = 0;
                repeat (2) @(negedge clk);
            end
            send_channel(tile, filter_id, ch, channels, replay);
        end
    endtask
    task automatic reject_replay(input bit first_marker = 1, input bit last_marker = 1);
        reuse_input = 1;
        first_ch = first_marker;
        last_ch = last_marker;
        valid = 1;
        repeat (3) begin
            @(negedge clk);
            if (ready) $fatal(1, "Invalid replay was accepted");
        end
        valid = 0;
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        reject_replay(); // No cached input after reset.
        send_channel(1, 0, 0, 4, 0);
        reject_replay(); // A partially loaded cache is unavailable.
        for (int ch=1; ch<4; ch++) send_channel(1, 0, ch, 4, 0);
        reject_replay(); // Cached group has four channels, not one.
        send_channel(1, 1, 0, 4, 1);
        reject_replay(1, 0); // Cannot restart in the middle of a replay.
        for (int ch=1; ch<4; ch++) send_channel(1, 1, ch, 4, 1);
        send_filter(1, 2, 4, 1, 1);
        send_filter(1, 3, 4, 1, 0);
        // Replacement groups of different lengths must invalidate stale channels.
        send_filter(2, 0, 1, 0, 0);
        send_filter(2, 1, 1, 1, 0);
        send_filter(3, 0, CACHE_CHANNELS, 0, 1);
        send_filter(3, 1, CACHE_CHANNELS, 1, 1);
        repeat (10) @(negedge clk);
        if (outputs != 8 || transforms != 5+CACHE_CHANNELS || reference_transforms != 18+2*CACHE_CHANNELS)
            $fatal(1, "Wrong totals: outputs=%0d transforms=%0d reference=%0d",
                   outputs, transforms, reference_transforms);
        // Reset during an unfinished replay must discard both cache and partial sum.
        send_channel(3, 2, 0, CACHE_CHANNELS, 1);
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        reject_replay();
        send_filter(4, 0, 1, 0, 0);
        send_filter(4, 1, 1, 1, 0);
        repeat (10) @(negedge clk);
        if (outputs != 10) $fatal(1, "Missing/extra outputs after reset");
        $display("PASS: sequential reuse, gaps, replacement, reset, rejection; cache depth=%0d", CACHE_CHANNELS);
        $finish;
    end
    initial begin
        #30000;
        $fatal(1, "Input reuse watchdog timeout");
    end
endmodule
