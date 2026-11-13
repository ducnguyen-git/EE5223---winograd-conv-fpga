`timescale 1ns / 1ps
module output_transform_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, valid_in = 0;
    logic signed [35:0] m_in [0:3][0:3];
    logic valid_raw, valid_scaled;
    logic signed [15:0] raw_out [0:1][0:1], scaled_out [0:1][0:1];

    output_transform_2d #(.SHIFT_BITS(0)) raw_dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .m_in(m_in),
        .valid_out(valid_raw), .y_out(raw_out));
    output_transform_2d #(.SHIFT_BITS(6)) scaled_dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .m_in(m_in),
        .valid_out(valid_scaled), .y_out(scaled_out));

    task automatic check_value(input longint signed value, input integer expected_scaled);
        longint signed expected_raw;
        expected_raw = (value > 32767) ? 32767 : ((value < -32768) ? -32768 : value);
        @(negedge clk);
        m_in[0][0] = 36'(value);
        valid_in = 1;
        @(negedge clk);
        valid_in = 0;
        while (!valid_raw || !valid_scaled) @(negedge clk);
        if (raw_out[0][0] !== 16'(expected_raw) || scaled_out[0][0] !== 16'(expected_scaled))
            $fatal(1, "Input %0d: raw=%0d expected=%0d, scaled=%0d expected=%0d",
                   value, raw_out[0][0], expected_raw, scaled_out[0][0], expected_scaled);
        for (int r=0; r<2; r++)
            for (int c=0; c<2; c++)
                if ((r != 0 || c != 0) && (raw_out[r][c] !== 0 || scaled_out[r][c] !== 0))
                    $fatal(1, "Unexpected nonzero output at [%0d,%0d]", r, c);
        @(negedge clk);
        if (valid_raw || valid_scaled) $fatal(1, "Unexpected extra output");
    endtask

    initial begin
        for (int r=0; r<4; r++)
            for (int c=0; c<4; c++) m_in[r][c] = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        check_value(0, 0);
        check_value(10, 0);
        check_value(31, 0);
        check_value(32, 1);
        check_value(33, 1);
        check_value(-31, 0);
        check_value(-32, 0); // Halfway cases round toward positive infinity.
        check_value(-33, -1);
        check_value(-95, -1);
        check_value(-96, -1);
        check_value(-97, -2);
        check_value(32767, 512);
        check_value(32768, 512);
        check_value(-32768, -512);
        check_value(-32769, -512);
        check_value(32767*64+31, 32767);
        check_value(32767*64+32, 32767);
        check_value(-32768*64-32, -32768);
        check_value(-32768*64-33, -32768);
        check_value(64'sd34359738367, 32767);
        check_value(-64'sd34359738368, -32768);
        $display("PASS: 21 rounding, saturation, and zero-shift cases");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "Output transform watchdog timeout");
    end
endmodule
