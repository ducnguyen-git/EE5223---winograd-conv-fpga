// =============================================================================
// Module: output_transform_1d
// Description: Multiplierless 1D Winograd output transform: Y = A^T * M
// Matrix: A^T = [[1, 1, 1, 0], [0, 1, -1, -1]]
// Formulas:
//   y[0] = m[0] + m[1] + m[2]
//   y[1] = m[1] - m[2] - m[3]
// =============================================================================
`timescale 1ns / 1ps

module output_transform_1d #(
    parameter IN_WIDTH  = 36,
    parameter OUT_WIDTH = 38
)(
    input  logic signed [IN_WIDTH-1:0]  m [0:3],
    output logic signed [OUT_WIDTH-1:0] y [0:1]
);
    // Sign-extended additions and subtractions
    assign y[0] = $signed({{ (OUT_WIDTH-IN_WIDTH){m[0][IN_WIDTH-1]} }, m[0]}) + 
                  $signed({{ (OUT_WIDTH-IN_WIDTH){m[1][IN_WIDTH-1]} }, m[1]}) + 
                  $signed({{ (OUT_WIDTH-IN_WIDTH){m[2][IN_WIDTH-1]} }, m[2]});

    assign y[1] = $signed({{ (OUT_WIDTH-IN_WIDTH){m[1][IN_WIDTH-1]} }, m[1]}) - 
                  $signed({{ (OUT_WIDTH-IN_WIDTH){m[2][IN_WIDTH-1]} }, m[2]}) - 
                  $signed({{ (OUT_WIDTH-IN_WIDTH){m[3][IN_WIDTH-1]} }, m[3]});

endmodule
