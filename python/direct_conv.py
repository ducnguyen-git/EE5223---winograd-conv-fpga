"""
Direct Convolution Software Reference Model
Author: Minh Duc / The Anh
Course: EE5223 - Advanced VLSI / Digital IC Design
"""

import numpy as np

def direct_conv2d_multi_channel(inputs, weights):
    """
    Direct spatial 2D convolution over Cin input channels for a single 4x4 spatial tile.
    inputs:  (Cin, 4, 4) array
    weights: (Cin, 3, 3) array
    Returns: (2, 2) output array
    """
    Cin = inputs.shape[0]
    out = np.zeros((2, 2), dtype=inputs.dtype)
    for r in range(2):
        for c in range(2):
            val = 0
            for k in range(Cin):
                val += np.sum(inputs[k, r:r+3, c:c+3] * weights[k, :, :])
            out[r, c] = val
    return out

if __name__ == "__main__":
    x = np.ones((4, 4, 4), dtype=np.int32)
    w = np.ones((4, 3, 3), dtype=np.int32)
    res = direct_conv2d_multi_channel(x, w)
    print("Multi-channel direct conv test shape:", res.shape, "Output values:\n", res)
