"""
Automated Stimulus & Golden Vector Generator for SystemVerilog Testbenches
Author: The Anh
Course: EE5223 - Advanced VLSI / Digital IC Design

Generates test stimulus files in hex format:
- tb/input.hex: 4x4 input activation tile(s)
- tb/weight.hex: 4x4 pre-transformed weights U
- tb/expected_output.hex: expected 2x2 output tile(s)
"""

import os
import numpy as np
from fixed_point import input_transform_2d, output_transform_2d, transform_weight_offline

def to_hex16(val):
    """Formats signed integer to 4-character 16-bit hex (two's complement)"""
    v = int(val) & 0xFFFF
    return f"{v:04x}"

def to_hex32(val):
    """Formats signed integer to 8-character 32-bit hex (two's complement)"""
    v = int(val) & 0xFFFFFFFF
    return f"{v:08x}"

def generate_verification_suite(num_tiles=20, cin=1, tb_dir="tb"):
    os.makedirs(tb_dir, exist_ok=True)
    np.random.seed(2026)

    input_file = os.path.join(tb_dir, "input.hex")
    weight_file = os.path.join(tb_dir, "weight.hex")
    expected_file = os.path.join(tb_dir, "expected_output.hex")
    expected_raw_file = os.path.join(tb_dir, "expected_raw.hex")

    with open(input_file, "w") as f_in, \
         open(weight_file, "w") as f_wt, \
         open(expected_file, "w") as f_exp, \
         open(expected_raw_file, "w") as f_raw:

        for t in range(num_tiles):
            # Accumulator across Cin
            Y_accum_raw = np.zeros((2, 2), dtype=np.int64)

            # Generate inputs and weights for each channel in this tile
            for c in range(cin):
                # INT16 input feature patch (-256 to 255 to prevent overflow without scaling)
                d = np.random.randint(-128, 128, size=(4, 4), dtype=np.int16)
                # Random 3x3 kernel
                g = np.random.uniform(-1.5, 1.5, size=(3, 3))
                U_float = transform_weight_offline(g)
                # Quantize U to signed INT16 (scale by 64 for fixed-point fraction)
                U_int = np.round(U_float * 64.0).astype(np.int16)

                # Write 16 values of d to input.hex (row-major)
                for val in d.flatten():
                    f_in.write(f"{to_hex16(val)}\n")

                # Write 16 values of U to weight.hex (row-major)
                for val in U_int.flatten():
                    f_wt.write(f"{to_hex16(val)}\n")

                # Compute hardware exact values
                V = input_transform_2d(d.astype(np.int64))
                M = V * U_int.astype(np.int64)
                Y_tile_raw = output_transform_2d(M)
                Y_accum_raw += Y_tile_raw

            # Requantize and clamp to INT16
            # Scale factor: 64 (shift right by 6)
            Y_scaled = np.right_shift(Y_accum_raw + 32, 6)
            Y_clamped = np.clip(Y_scaled, -32768, 32767).astype(np.int16)

            # Write 4 values of Y to expected_output.hex
            for val in Y_clamped.flatten():
                f_exp.write(f"{to_hex16(val)}\n")

            for val in Y_accum_raw.flatten():
                f_raw.write(f"{to_hex32(val)}\n")

    print(f"Generated {num_tiles} test vector tiles (Cin={cin}) into directory '{tb_dir}/'")

if __name__ == "__main__":
    generate_verification_suite(num_tiles=50, cin=1, tb_dir="tb")
