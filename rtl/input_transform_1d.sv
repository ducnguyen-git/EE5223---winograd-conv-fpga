// =============================================================================
// Module: input_transform_1d
// Description: Multiplierless 1D Winograd input transform: V = B^T * d
// Formulas:
//   v[0] = d[0] - d[2]
//   v[1] = d[1] + d[2]
//   v[2] = d[2] - d[1]
//   v[3] = d[1] - d[3]
// =============================================================================
`timescale 1ns / 1ps

module input_transform_1d #(
    parameter DATA_WIDTH = 16,
    parameter OUT_WIDTH  = 18
)(
    input  logic signed [DATA_WIDTH-1:0] d [0:3],
    output logic signed [OUT_WIDTH-1:0]  v [0:3]
);
    // Sign-extended additions and subtractions (no DSP blocks needed)
    assign v[0] = $signed({{ (OUT_WIDTH-DATA_WIDTH){d[0][DATA_WIDTH-1]} }, d[0]}) - 
                  $signed({{ (OUT_WIDTH-DATA_WIDTH){d[2][DATA_WIDTH-1]} }, d[2]});

    assign v[1] = $signed({{ (OUT_WIDTH-DATA_WIDTH){d[1][DATA_WIDTH-1]} }, d[1]}) + 
                  $signed({{ (OUT_WIDTH-DATA_WIDTH){d[2][DATA_WIDTH-1]} }, d[2]});

    assign v[2] = $signed({{ (OUT_WIDTH-DATA_WIDTH){d[2][DATA_WIDTH-1]} }, d[2]}) - 
                  $signed({{ (OUT_WIDTH-DATA_WIDTH){d[1][DATA_WIDTH-1]} }, d[1]});

    assign v[3] = $signed({{ (OUT_WIDTH-DATA_WIDTH){d[1][DATA_WIDTH-1]} }, d[1]}) - 
                  $signed({{ (OUT_WIDTH-DATA_WIDTH){d[3][DATA_WIDTH-1]} }, d[3]});

endmodule
