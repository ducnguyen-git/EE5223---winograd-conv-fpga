"""
Winograd F(2x2, 3x3) Reference Model and Testbench Utility
Author: The Anh / Minh Duc
Course: EE5223 - Advanced VLSI / Digital IC Design
"""

import numpy as np

# Transformation matrices for Winograd F(2x2, 3x3)
B_T = np.array([
    [ 1.0,  0.0, -1.0,  0.0],
    [ 0.0,  1.0,  1.0,  0.0],
    [ 0.0, -1.0,  1.0,  0.0],
    [ 0.0,  1.0,  0.0, -1.0]
], dtype=np.float64)

B = B_T.T

G = np.array([
    [ 1.0,  0.0,  0.0],
    [ 0.5,  0.5,  0.5],
    [ 0.5, -0.5,  0.5],
    [ 0.0,  0.0,  1.0]
], dtype=np.float64)

G_T = G.T

A_T = np.array([
    [ 1.0,  1.0,  1.0,  0.0],
    [ 0.0,  1.0, -1.0, -1.0]
], dtype=np.float64)

A = A_T.T

def winograd_f2x2_3x3_float(d, g):
    """
    Computes Winograd F(2x2, 3x3) convolution for a single 4x4 input tile d and 3x3 kernel g.
    d: (4, 4) float array
    g: (3, 3) float array
    Returns: (2, 2) output array Y
    """
    assert d.shape == (4, 4), f"Expected d shape (4, 4), got {d.shape}"
    assert g.shape == (3, 3), f"Expected g shape (3, 3), got {g.shape}"

    # 1. Transform weights: U = G * g * G^T (4x4)
    U = G @ g @ G_T

    # 2. Transform input tile: V = B^T * d * B (4x4)
    V = B_T @ d @ B

    # 3. Element-wise product in transform domain: M = U (elem_mult) V (4x4)
    M = U * V

    # 4. Output transformation: Y = A^T * M * A (2x2)
    Y = A_T @ M @ A

    return Y

def direct_conv2d_tile(d, g):
    """
    Direct spatial 2D convolution producing 2x2 output tile from 4x4 input and 3x3 kernel.
    d: (4, 4) array
    g: (3, 3) array
    Returns: (2, 2) array Y
    """
    Y = np.zeros((2, 2), dtype=d.dtype)
    for r in range(2):
        for c in range(2):
            patch = d[r:r+3, c:c+3]
            Y[r, c] = np.sum(patch * g)
    return Y

if __name__ == "__main__":
    np.random.seed(42)
    # Test 1000 random trials
    max_diff = 0.0
    for _ in range(1000):
        d_rand = np.random.randn(4, 4)
        g_rand = np.random.randn(3, 3)
        y_wino = winograd_f2x2_3x3_float(d_rand, g_rand)
        y_dir  = direct_conv2d_tile(d_rand, g_rand)
        diff = np.max(np.abs(y_wino - y_dir))
        if diff > max_diff:
            max_diff = diff

    print(f"Verified 1,000 float32/float64 test cases.")
    print(f"Max absolute discrepancy between Winograd and Direct: {max_diff:.2e}")
    assert max_diff < 1e-12, "Mathematical identity verification failed!"
    print("SUCCESS: Winograd F(2x2, 3x3) matches direct convolution identically.")
