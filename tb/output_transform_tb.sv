// =============================================================================
// Testbench: output_transform_tb
// Description: Unit testbench for output_transform_2d
// Self-checking with automated mismatch counter
// =============================================================================
`timescale 1ns / 1ps

module output_transform_tb;

    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic signed [35:0] m_in [0:3][0:3];
    logic        valid_out;
    logic signed [15:0] y_out [0:1][0:1];

    output_transform_2d #(
        .IN_WIDTH(36),
        .INTER_WIDTH(38),
        .FINAL_WIDTH(40),
        .OUT_WIDTH(16),
        .SHIFT_BITS(0) // No shift for raw check
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .m_in(m_in),
        .valid_out(valid_out),
        .y_out(y_out)
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
                m_in[r][c] = 0;

        #20;
        rst_n = 1;
        #10;

        // Apply M where only M[0][0] = 10
        // A^T = [[1,1,1,0],[0,1,-1,-1]]
        // Column 0: A^T * [10,0,0,0]^T = [10, 0]^T
        // Other columns: 0
        // Row 0: A^T * [10,0,0,0]^T = [10, 0]^T
        // Expected Y: Y[0][0] = 10, all others 0
        @(posedge clk);
        valid_in <= 1'b1;
        m_in[0][0] <= 36'sd10;

        @(posedge clk);
        valid_in <= 1'b0;

        while (!valid_out) @(posedge clk);

        if (y_out[0][0] !== 16'sd10) begin
            $display("[FAIL] Expected y_out[0][0] = 10, got %0d", y_out[0][0]);
            errors++;
        end else begin
            $display("[PASS] Output transform delta test: y_out[0][0] = 10 verified.");
        end

        #20;
        if (errors == 0) begin
            $display("==================================================");
            $display("SUCCESS: output_transform_tb passed all tests!");
            $display("==================================================");
        end else begin
            $display("FAILURE: %0d errors in output_transform_tb!", errors);
        end
        $finish;
    end

endmodule
