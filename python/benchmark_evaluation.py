"""
Comprehensive Architectural Benchmarking and Numerical Error Analysis
Author: The Anh
Course: EE5223 - Advanced VLSI / Digital IC Design
"""

import numpy as np
from winograd import winograd_f2x2_3x3_float, direct_conv2d_tile
from fixed_point import winograd_fixed_point_tile, transform_weight_offline

def evaluate_accuracy_and_metrics(num_trials=2000):
    print("="*65)
    print(" EE5223: WINOGRAD F(2x2, 3x3) vs DIRECT CONV BENCHMARKING ")
    print("="*65)

    np.random.seed(42)

    psnr_list = []
    mse_list  = []
    max_err_list = []

    for _ in range(num_trials):
        # Generate random inputs and weights
        d_fp = np.random.uniform(-1.0, 1.0, size=(4, 4))
        g_fp = np.random.uniform(-1.0, 1.0, size=(3, 3))

        # Floating-point golden output
        y_gold = direct_conv2d_tile(d_fp, g_fp)

        # Quantize to INT16 (scale by 256)
        d_int = np.clip(np.round(d_fp * 256.0), -32768, 32767).astype(np.int16)
        u_float = transform_weight_offline(g_fp)
        u_int = np.clip(np.round(u_float * 256.0), -32768, 32767).astype(np.int16)

        # Fixed point execution
        _, y_fxp = winograd_fixed_point_tile(d_int, u_int, shift_out=8)

        # Re-convert fixed point to float for comparison
        y_fxp_fp = y_fxp / 256.0

        mse = np.mean((y_gold - y_fxp_fp) ** 2)
        mse_list.append(mse)

        peak_val = max(np.max(np.abs(y_gold)), 1e-6)
        if mse > 1e-12:
            snr = 10 * np.log10((peak_val ** 2) / mse)
        else:
            snr = 120.0
        psnr_list.append(snr)
        max_err_list.append(np.max(np.abs(y_gold - y_fxp_fp)))

    avg_mse = np.mean(mse_list)
    avg_psnr = np.mean(psnr_list)
    max_abs_err = np.max(max_err_list)

    print(f"Number of Evaluation Tiles Tested : {num_trials}")
    print(f"Mean Squared Error (MSE)           : {avg_mse:.6e}")
    print(f"Average Signal-to-Noise Ratio (SNR): {avg_psnr:.2f} dB")
    print(f"Maximum Absolute Numerical Error   : {max_abs_err:.6e}")
    print("\nHardware Complexity Comparison:")
    print("-" * 65)
    print(f"{'Metric':<30} | {'Direct Conv':<15} | {'Winograd F(2x2, 3x3)':<15}")
    print("-" * 65)
    print(f"{'Multiplications / 2x2 tile':<30} | {36:<15} | {16:<15}")
    print(f"{'DSP Multipliers (Parallel)':<30} | {36:<15} | {16:<15}")
    print(f"{'Arithmetic Multiplication Speedup':<30} | {'1.00x':<15} | {'2.25x':<15}")
    print(f"{'Transform Adders / Subtractors':<30} | {0:<15} | {32:<15}")
    print(f"{'Execution Latency (Pipelined)':<30} | {'36 cycles / MAC':<15} | {'6 cycles total':<15}")
    print("=" * 65)

    # Save summary report to results/benchmark_summary.txt
    with open("results/benchmark_summary.txt", "w") as f:
        f.write("EE5223 Winograd Accelerator Evaluation Summary\n")
        f.write(f"Tested Tiles: {num_trials}\n")
        f.write(f"Average SNR: {avg_psnr:.2f} dB\n")
        f.write(f"Average MSE: {avg_mse:.6e}\n")
        f.write("Multiplication Reduction: 2.25x (16 DSPs vs 36 DSPs)\n")

if __name__ == "__main__":
    evaluate_accuracy_and_metrics()
