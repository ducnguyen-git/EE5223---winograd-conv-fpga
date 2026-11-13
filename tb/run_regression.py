"""Run Winograd RTL checks with isolated builds and generated vectors."""
import os
from pathlib import Path
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from generate_vectors import generate_verification_suite


def main():
    # Expected-failure checks should not leave simulator core dumps behind.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix="winograd-regression-") as directory:
        temp = Path(directory)
        env = {**os.environ, "CCACHE_DIR": str(temp / "ccache")}
        sources = sorted(str(p) for p in (ROOT / "rtl").glob("*.sv"))
        cases = [("output_transform_tb", {}), ("parameter_widths_tb", {}), ("input_reuse_tb", {}),
                 ("input_reuse_tb", {"CACHE_CHANNELS": 5})]
        cases += [("line_buffer_tb", {}), ("stream_top_tb", {}),
                  ("stream_top_tb", {"IMAGE_WIDTH": 4, "IMAGE_HEIGHT": 4, "CHANNELS": 1, "FILTERS": 1}),
                  ("stream_top_tb", {"IMAGE_WIDTH": 8, "IMAGE_HEIGHT": 6, "CHANNELS": 2, "FILTERS": 2})]
        cases += [("winograd_core_tb", {"CIN": cin, "INSERT_GAPS": gaps})
                  for cin, gaps in [(1, 0), (4, 0), (4, 1), (64, 1)]]
        cases += [("winograd_core_tb", {"CIN": 1, "INSERT_GAPS": 0, "PARALLEL_DSPS": dsps})
                  for dsps in (4, 8)]
        for index, (top, parameters) in enumerate(cases):
            build = temp / f"build-{index}"
            command = ["verilator", "--binary", "--assert", "--timing", "-Wno-fatal",
                       "--top-module", top, "--Mdir", str(build)]
            command += [f"-G{k}={v}" for k, v in parameters.items()]
            command += sources + [str(ROOT / "tb" / f"{top}.sv")]
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
            if result.returncode:
                sys.exit(result.stdout + result.stderr)
            run = [str(build / f"V{top}")]
            if top == "winograd_core_tb":
                vectors = temp / f"vectors-{index}"
                generate_verification_suite(num_tiles=50, cin=parameters["CIN"], tb_dir=str(vectors))
                run.append(f"+VECTOR_DIR={vectors}")
            result = subprocess.run(run, cwd=ROOT, capture_output=True, text=True, timeout=30)
            if parameters.get("PARALLEL_DSPS", 16) != 16:
                if result.returncode == 0 or "supports only PARALLEL_DSPS=16" not in result.stdout + result.stderr:
                    sys.exit("FAIL: unsupported multiplier count was not rejected")
                print(f"PASS: rejected PARALLEL_DSPS={parameters['PARALLEL_DSPS']}")
                continue
            if result.returncode:
                sys.exit(result.stdout + result.stderr)
            print(f"PASS: {top} {parameters}")
            if top == "winograd_core_tb" and parameters == {"CIN": 1, "INSERT_GAPS": 0}:
                expected = vectors / "expected_output.hex"
                lines = expected.read_text().splitlines()
                lines[0] = f"{int(lines[0], 16) ^ 1:04x}"
                expected.write_text("\n".join(lines) + "\n")
                result = subprocess.run(run, cwd=ROOT, capture_output=True, text=True, timeout=30)
                if result.returncode == 0 or "Mismatches detected" not in result.stdout + result.stderr:
                    sys.exit("FAIL: corrupted expected output did not fail the simulation")
                print("PASS: corrupted expected output returns failure")
        print("All Winograd RTL regressions passed.")


if __name__ == "__main__":
    main()
