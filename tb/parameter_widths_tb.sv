`timescale 1ns / 1ps
module parameter_widths_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, valid = 0, first_ch = 0, last_ch = 0;
    logic signed [7:0] d [0:3][0:3], u [0:3][0:3];
    logic ready, out_valid;
    logic signed [7:0] y [0:1][0:1];
    winograd_top #(.DATA_IN_WIDTH(8), .U_WIDTH(8), .DATA_OUT_WIDTH(8),
                   .MAX_CHANNELS(64), .SHIFT_BITS(0)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(valid), .in_ready(ready),
        .d_tile(d), .u_tile(u), .first_ch(first_ch), .last_ch(last_ch), .reuse_input(1'b0),
        .out_valid(out_valid), .y_tile(y));

    logic signed [33:0] products [0:3][0:3];
    logic signed [39:0] sums [0:3][0:3];
    logic sum_valid;
    channel_accumulator #(.MAX_CHANNELS(64)) acc (
        .clk(clk), .rst_n(rst_n), .valid_in(valid),
        .first_channel(first_ch), .last_channel(last_ch), .m_in(products),
        .valid_out(sum_valid), .m_accum_out(sums));

    task automatic check_tile(input integer value);
        @(negedge clk);
        for (int r=0; r<4; r++) begin
            for (int c=0; c<4; c++) begin
                d[r][c] = 0;
                u[r][c] = 0;
                products[r][c] = (value < 0) ? -34'sd8589934592 : 34'sd8589934591;
            end
        end
        d[0][0] = 8'(value);
        u[0][0] = 1;
        for (int ch=0; ch<64; ch++) begin
            valid = 1;
            first_ch = (ch == 0);
            last_ch = (ch == 63);
            @(negedge clk);
        end
        valid = 0;
        first_ch = 0;
        last_ch = 0;
        assert (sum_valid) else $fatal(1, "Missing channel sum");
        for (int r=0; r<4; r++)
            for (int c=0; c<4; c++)
                assert (sums[r][c] == ((value < 0) ? -40'sd549755813888 : 40'sd549755813824))
                    else $fatal(1, "64-channel accumulation overflow");
        while (!out_valid) @(negedge clk);
        assert (y[0][0] == ((value == 1) ? 64 : ((value < 0) ? -128 : 127)))
            else $fatal(1, "Incorrect scaled/saturated output: %0d", y[0][0]);
        assert (y[0][1] == 0 && y[1][0] == 0 && y[1][1] == 0)
            else $fatal(1, "Unexpected output elements");
    endtask

    initial begin
        assert ($bits(dut.v_matrix[0][0]) == 10 &&
                $bits(dut.m_matrix[0][0]) == 18 &&
                $bits(dut.m_accum[0][0]) == 24 &&
                $bits(dut.u_output_trans.row_res[0][0]) == 28)
            else $fatal(1, "Widths were not derived from parameters");
        repeat (2) @(negedge clk);
        rst_n = 1;
        check_tile(1);
        check_tile(127);
        check_tile(-128);
        $display("PASS: derived widths, 64-channel extremes, zero shift, signed 8-bit saturation");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "Timeout");
    end
endmodule
