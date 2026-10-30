"""
Fixed-Point Quantization Model & Hardware-Equivalent Simulator
Author: The Anh
Course: EE5223 - Advanced VLSI / Digital IC Design

Precision specifications:
- Input activations: signed 16-bit (Q8.8 or integer)
- Pre-transformed weights U: signed 16-bit
- Input transform V = B^T * d * B: 18-bit signed (2 additions per dimension -> +2 bits max dynamic range)
- Multiplier product M = U * V: 34-bit signed (16-bit * 18-bit)
- Channel accumulation: 36-bit signed (supports up to Cin=4 accumulation headroom)
- Output transform Y = A^T * M * A: intermediate 38-bit signed
- Final saturation & requantization: 16-bit signed
"""

import numpy as np

# Integer-equivalent 1D Winograd Transforms
def transform_1d_input(d):
    """
    Multiplierless 1D input transform: v = B^T * d
    B^T = [
      [ 1,  0, -1,  0],
      [ 0,  1,  1,  0],
      [ 0, -1,  1,  0],
      [ 0,  1,  0, -1]
    ]
    d: vector of length 4 (int64)
    v: vector of length 4 (int64)
    """
    v0 = d[0] - d[2]
    v1 = d[1] + d[2]
    v2 = d[2] - d[1]
    v3 = d[1] - d[3]
    return np.array([v0, v1, v2, v3], dtype=np.int64)

def input_transform_2d(d):
    """
    Separable 2D input transform: V = B^T * d * B = (B^T * (B^T * d^T)^T)
    d: (4, 4) 2D array
    Returns: (4, 4) 2D array V
    """
    # Step 1: Column transform (transform each column of d)
    temp = np.zeros((4, 4), dtype=np.int64)
    for col in range(4):
        temp[:, col] = transform_1d_input(d[:, col])
    
    # Step 2: Row transform (transform each row of temp)
    V = np.zeros((4, 4), dtype=np.int64)
    for row in range(4):
        V[row, :] = transform_1d_input(temp[row, :])
    return V

def transform_1d_output(m):
    """
    Multiplierless 1D output transform: y = A^T * m
    A^T = [
      [ 1,  1,  1,  0],
      [ 0,  1, -1, -1]
    ]
    m: vector of length 4 (int64)
    y: vector of length 2 (int64)
    """
    y0 = m[0] + m[1] + m[2]
    y1 = m[1] - m[2] - m[3]
    return np.array([y0, y1], dtype=np.int64)

def output_transform_2d(M):
    """
    Separable 2D output transform: Y = A^T * M * A
    M: (4, 4) intermediate product matrix
    Returns: (2, 2) output matrix Y
    """
    # Step 1: Column transform on 4 columns -> (2, 4)
    temp = np.zeros((2, 4), dtype=np.int64)
    for col in range(4):
        temp[:, col] = transform_1d_output(M[:, col])
    
    # Step 2: Row transform on 2 rows -> (2, 2)
    Y = np.zeros((2, 2), dtype=np.int64)
    for row in range(2):
        Y[row, :] = transform_1d_output(temp[row, :])
    return Y

def transform_weight_offline(g):
    """
    Transforms 3x3 kernel g into 4x4 Winograd domain weights U = G * g * G^T.
    Returns: (4, 4) float array
    """
    G_mat = np.array([
        [ 1.0,  0.0,  0.0],
        [ 0.5,  0.5,  0.5],
        [ 0.5, -0.5,  0.5],
        [ 0.0,  0.0,  1.0]
    ], dtype=np.float64)
    return G_mat @ g @ G_mat.T

def winograd_fixed_point_tile(d_int16, u_int16, shift_out=8):
    """
    Complete bit-level hardware-equivalent simulation for 1 tile.
    d_int16: (4, 4) array in signed INT16
    u_int16: (4, 4) array in signed INT16 (pre-scaled and quantized weights)
    shift_out: right shift for fixed-point fractional requantization
    """
    # 1. Input transform (int16 -> int18)
    V = input_transform_2d(d_int16.astype(np.int64))

    # 2. Multiplier array (int18 * int16 -> int34)
    M = V * u_int16.astype(np.int64)

    # 3. Output transform (int34 -> int38)
    Y_raw = output_transform_2d(M)

    # 4. Scaling / requantization and saturation to INT16
    if shift_out > 0:
        Y_scaled = np.right_shift(Y_raw + (1 << (shift_out - 1)), shift_out) # with rounding
    else:
        Y_scaled = Y_raw

    Y_clamped = np.clip(Y_scaled, -32768, 32767).astype(np.int16)
    return Y_raw, Y_clamped

if __name__ == "__main__":
    d = np.array([
        [ 10, -5,  3,  8],
        [  2,  4, -1,  0],
        [ -6,  7, 12, -4],
        [  1, -3,  5,  2]
    ], dtype=np.int16)

    # Simple kernel
    g = np.array([
        [ 1, 0, -1],
        [ 2, 1,  0],
        [ 0, 1, -1]
    ], dtype=np.float64)

    U = transform_weight_offline(g)
    U_int = np.round(U * 256.0).astype(np.int16) # Q8.8 format

    Y_raw, Y_sat = winograd_fixed_point_tile(d, U_int, shift_out=8)
    print("Fixed-point raw output:\n", Y_raw)
    print("Fixed-point quantized (INT16) output:\n", Y_sat)
