// =============================================================================
// Testbench: direct_conv_tb
// Description: Unit testbench for direct_conv_top baseline
// Verifies 2x2 direct convolution with 36 DSP multiplications
// =============================================================================
`timescale 1ns / 1ps

module direct_conv_tb;

    logic        clk;
    logic        rst_n;
    logic        in_valid;
    logic        in_ready;
    logic signed [15:0] d_tile [0:3][0:3];
    logic signed [15:0] w_kernel [0:2][0:2];
    logic        first_ch;
    logic        last_ch;
    logic        out_valid;
    logic signed [15:0] y_tile [0:1][0:1];

    direct_conv_top #(
        .DATA_IN_WIDTH(16),
        .WEIGHT_WIDTH(16),
        .PROD_WIDTH(32),
        .ACCUM_WIDTH(36),
        .DATA_OUT_WIDTH(16),
        .SHIFT_BITS(0) // raw check without shift
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .d_tile(d_tile),
        .w_kernel(w_kernel),
        .first_ch(first_ch),
        .last_ch(last_ch),
        .out_valid(out_valid),
        .y_tile(y_tile)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int errors = 0;

    initial begin
        rst_n = 0;
        in_valid = 0;
        first_ch = 0;
        last_ch  = 0;

        #20;
        rst_n = 1;
        #10;

        // Apply d_tile all 1s, w_kernel all 1s
        // Each 3x3 dot product has 9 multiplications of 1*1 = 9
        // Output for all 4 pixels should be 9
        @(posedge clk);
        in_valid <= 1'b1;
        first_ch <= 1'b1;
        last_ch  <= 1'b1;

        for (int r = 0; r < 4; r++)
            for (int c = 0; c < 4; c++)
                d_tile[r][c] <= 16'sd1;

        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                w_kernel[r][c] <= 16'sd1;

        @(posedge clk);
        in_valid <= 1'b0;

        while (!out_valid) @(posedge clk);

        for (int r = 0; r < 2; r++) begin
            for (int c = 0; c < 2; c++) begin
                if (y_tile[r][c] !== 16'sd9) begin
                    $display("[FAIL] Expected y_tile[%0d][%0d] = 9, got %0d", r, c, y_tile[r][c]);
                    errors++;
                end
            end
        end

        if (errors == 0) begin
            $display("[PASS] Direct Conv baseline all-ones test: all 4 output pixels equal 9.");
            $display("==================================================");
            $display("SUCCESS: direct_conv_tb passed all tests!");
            $display("==================================================");
        end else begin
            $display("FAILURE: %0d errors in direct_conv_tb!", errors);
        end
        $finish;
    end

endmodule
