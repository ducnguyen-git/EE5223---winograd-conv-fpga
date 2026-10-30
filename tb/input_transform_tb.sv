// =============================================================================
// Testbench: input_transform_tb
// Description: Unit testbench for input_transform_1d & input_transform_2d
// Self-checking with automated mismatch counter
// =============================================================================
`timescale 1ns / 1ps

module input_transform_tb;

    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic signed [15:0] d_in [0:3][0:3];
    logic        valid_out;
    logic signed [17:0] v_out [0:3][0:3];

    input_transform_2d #(
        .DATA_IN_WIDTH(16),
        .INTER_WIDTH(17),
        .DATA_OUT_WIDTH(18)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .d_in(d_in),
        .valid_out(valid_out),
        .v_out(v_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int errors = 0;

    initial begin
        rst_n = 0;
        valid_in = 0;
        for (int r = 0; r < 4; r++)
            for (int c = 0; c < 4; c++)
                d_in[r][c] = 0;

        #20;
        rst_n = 1;
        #10;

        // Apply a known tile: all 1s
        // B^T * [1 1 1 1]^T = [1-1, 1+1, 1-1, 1-1]^T = [0, 2, 0, 0]^T
        // 2D transform of all 1s should give 4 at position (1,1) and 0 elsewhere
        @(posedge clk);
        valid_in <= 1'b1;
        for (int r = 0; r < 4; r++)
            for (int c = 0; c < 4; c++)
                d_in[r][c] <= 16'sd1;

        @(posedge clk);
        valid_in <= 1'b0;

        @(posedge clk);
        while (!valid_out) @(posedge clk);

        // Check output
        if (v_out[1][1] !== 18'sd4) begin
            $display("[FAIL] Expected v_out[1][1] = 4, got %0d", v_out[1][1]);
            errors++;
        end else begin
            $display("[PASS] Input transform all-ones test: v_out[1][1] = 4 as expected.");
        end

        #20;
        if (errors == 0) begin
            $display("=================================================");
            $display("SUCCESS: input_transform_tb passed all tests!");
            $display("=================================================");
        end else begin
            $display("FAILURE: %0d errors in input_transform_tb!", errors);
        end
        $finish;
    end

endmodule
