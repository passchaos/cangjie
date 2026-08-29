#!/usr/bin/env python3
"""Run a symmetric Cangjie/FreeType raster and bitmap lifecycle matrix."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Case:
    name: str
    font: Path
    codepoint: str


def run(command: list[str], cpu: int | None) -> dict[str, str]:
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    completed = subprocess.run(
        command, check=False, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr, end="")
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}"
        )
    fields: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", completed.stdout):
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def command(
    executable: Path, case: Case, engine: str, mode: str, size: int,
    iterations: int, samples: int, target_size: int,
) -> list[str]:
    return [
        str(executable), "--engine", engine, "--mode", mode,
        "--font", str(case.font), "--codepoint", case.codepoint,
        "--font-size", str(size), "--target-size", str(target_size),
        "--iterations", str(iterations), "--warmup",
        str(max(1, iterations // 10)), "--samples", str(samples),
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glyph-bench", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--cff", required=True, type=Path)
    parser.add_argument("--cff2", required=True, type=Path)
    parser.add_argument("--arabic", required=True, type=Path)
    parser.add_argument("--cjk", required=True, type=Path)
    parser.add_argument("--cbdt", type=Path)
    parser.add_argument("--sbix", type=Path)
    parser.add_argument("--colr-v0", type=Path)
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--sizes", default="8,16,32,64,128")
    parser.add_argument("--minimum-target-size", type=int, default=32)
    parser.add_argument(
        "--fail-on-slower",
        action="store_true",
        help="fail when Cangjie is not faster in any measured lifecycle row",
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0 or args.minimum_target_size <= 0:
        parser.error("iterations, samples, and minimum target size must be positive")
    try:
        sizes = tuple(int(item) for item in args.sizes.split(","))
    except ValueError:
        parser.error("sizes must be a comma-separated integer list")
    if not sizes or any(size <= 0 for size in sizes):
        parser.error("sizes must be positive")
    for label, path in (
        ("cbdt", args.cbdt),
        ("sbix", args.sbix),
        ("colr-v0", args.colr_v0),
    ):
        if path is not None and not path.is_file():
            parser.error(f"{label} fixture does not exist: {path}")

    cases = (
        Case("glyf-latin", args.roboto, "U+00E9"),
        Case("cff1-latin", args.cff, "U+00E9"),
        Case("cff2-latin", args.cff2, "U+0041"),
        Case("glyf-arabic", args.arabic, "U+0633"),
        Case("cff-cjk", args.cjk, "U+6F22"),
    )
    bitmap_cases = (
        (() if args.cbdt is None else (
            Case("cbdt-png", args.cbdt, "U+0038"),
        )) +
        (() if args.sbix is None else (
            Case("sbix-png", args.sbix, "U+0058"),
        ))
    )
    failures: list[str] = []
    row_count = 0
    for case in cases:
        # Parsing is independent of glyph and size. Run one resident-byte
        # cold-face lifecycle per representative format before raster rows.
        cangjie_cmd = command(
            args.glyph_bench, case, "cangjie", "face-open", 16,
            args.iterations, args.samples, args.minimum_target_size,
        )
        freetype_cmd = command(
            args.glyph_bench, case, "freetype", "face-open", 16,
            args.iterations, args.samples, args.minimum_target_size,
        )
        cangjie_a = run(cangjie_cmd, args.cpu)
        freetype_a = run(freetype_cmd, args.cpu)
        freetype_b = run(freetype_cmd, args.cpu)
        cangjie_b = run(cangjie_cmd, args.cpu)
        for engine, first, second in (
            ("cangjie", cangjie_a, cangjie_b),
            ("freetype", freetype_a, freetype_b),
        ):
            if first.get("checksum") != second.get("checksum"):
                failures.append(
                    f"{case.name}/face-open: {engine} checksum "
                    f"{first.get('checksum')}/{second.get('checksum')}"
                )
        if cangjie_a.get("checksum") != freetype_a.get("checksum"):
            failures.append(
                f"{case.name}/face-open: cross-engine properties "
                f"{cangjie_a.get('checksum')}/{freetype_a.get('checksum')}"
            )
        cangjie_ns = math.sqrt(
            float(cangjie_a["sample_median_ns_per_iter"])
            * float(cangjie_b["sample_median_ns_per_iter"])
        )
        freetype_ns = math.sqrt(
            float(freetype_a["sample_median_ns_per_iter"])
            * float(freetype_b["sample_median_ns_per_iter"])
        )
        speedup = math.inf if cangjie_ns == 0 else freetype_ns / cangjie_ns
        print(
            f"{case.name}/face-open: "
            f"cangjie={cangjie_ns:.3f}ns freetype={freetype_ns:.3f}ns "
            f"speedup={speedup:.3f}x"
        )
        if args.fail_on_slower and speedup <= 1.0:
            failures.append(
                f"{case.name}/face-open: performance "
                f"{cangjie_ns:.3f}ns/{freetype_ns:.3f}ns"
            )
        row_count += 1
        for mode in ("raster", "raster-owning", "raster-reuse"):
            for size in sizes:
                # Size the surface to the glyph instead of letting a fixed
                # 256x256 clear/hash hide scan conversion at small ppem.
                target_size = max(args.minimum_target_size, size * 2)
                cangjie_cmd = command(
                    args.glyph_bench, case, "cangjie", mode, size,
                    args.iterations, args.samples, target_size,
                )
                freetype_cmd = command(
                    args.glyph_bench, case, "freetype", mode, size,
                    args.iterations, args.samples, target_size,
                )
                # Separate processes in A/B/B/A order avoid compare mode's
                # fixed engine order and make frequency drift visible.
                cangjie_a = run(cangjie_cmd, args.cpu)
                freetype_a = run(freetype_cmd, args.cpu)
                freetype_b = run(freetype_cmd, args.cpu)
                cangjie_b = run(cangjie_cmd, args.cpu)
                for engine, first, second in (
                    ("cangjie", cangjie_a, cangjie_b),
                    ("freetype", freetype_a, freetype_b),
                ):
                    if first.get("checksum") != second.get("checksum"):
                        failures.append(
                            f"{case.name}/{mode}/{size}: {engine} checksum "
                            f"{first.get('checksum')}/{second.get('checksum')}"
                        )
                cangjie_ns = math.sqrt(
                    float(cangjie_a["sample_median_ns_per_iter"])
                    * float(cangjie_b["sample_median_ns_per_iter"])
                )
                freetype_ns = math.sqrt(
                    float(freetype_a["sample_median_ns_per_iter"])
                    * float(freetype_b["sample_median_ns_per_iter"])
                )
                speedup = math.inf if cangjie_ns == 0 else freetype_ns / cangjie_ns
                print(
                    f"{case.name}/{mode}/{size}px: "
                    f"cangjie={cangjie_ns:.3f}ns freetype={freetype_ns:.3f}ns "
                    f"speedup={speedup:.3f}x"
                )
                if args.fail_on_slower and speedup <= 1.0:
                    failures.append(
                        f"{case.name}/{mode}/{size}: performance "
                        f"{cangjie_ns:.3f}ns/{freetype_ns:.3f}ns"
                    )
                row_count += 1
    for case in bitmap_cases:
        for size in sizes:
            # Compare decoded native strike output rather than differently
            # scaled destination surfaces. Both engines hash dimensions,
            # authored placement, and normalized mask8 or premultiplied BGRA.
            cangjie_cmd = command(
                args.glyph_bench, case, "cangjie", "bitmap-render", size,
                args.iterations, args.samples, args.minimum_target_size,
            )
            freetype_cmd = command(
                args.glyph_bench, case, "freetype", "bitmap-render", size,
                args.iterations, args.samples, args.minimum_target_size,
            )
            cangjie_a = run(cangjie_cmd, args.cpu)
            freetype_a = run(freetype_cmd, args.cpu)
            freetype_b = run(freetype_cmd, args.cpu)
            cangjie_b = run(cangjie_cmd, args.cpu)
            for engine, first, second in (
                ("cangjie", cangjie_a, cangjie_b),
                ("freetype", freetype_a, freetype_b),
            ):
                if first.get("checksum") != second.get("checksum"):
                    failures.append(
                        f"{case.name}/bitmap-render/{size}: {engine} "
                        f"checksum {first.get('checksum')}/"
                        f"{second.get('checksum')}"
                    )
            if cangjie_a.get("checksum") != freetype_a.get("checksum"):
                failures.append(
                    f"{case.name}/bitmap-render/{size}: cross-engine pixels "
                    f"{cangjie_a.get('checksum')}/"
                    f"{freetype_a.get('checksum')}"
                )
            cangjie_ns = math.sqrt(
                float(cangjie_a["sample_median_ns_per_iter"])
                * float(cangjie_b["sample_median_ns_per_iter"])
            )
            freetype_ns = math.sqrt(
                float(freetype_a["sample_median_ns_per_iter"])
                * float(freetype_b["sample_median_ns_per_iter"])
            )
            speedup = math.inf if cangjie_ns == 0 else freetype_ns / cangjie_ns
            print(
                f"{case.name}/bitmap-render/{size}px: "
                f"cangjie={cangjie_ns:.3f}ns freetype={freetype_ns:.3f}ns "
                f"speedup={speedup:.3f}x"
            )
            if args.fail_on_slower and speedup <= 1.0:
                failures.append(
                    f"{case.name}/bitmap-render/{size}: performance "
                    f"{cangjie_ns:.3f}ns/{freetype_ns:.3f}ns"
                )
            row_count += 1
    if args.colr_v0 is not None:
        case = Case("colr-v0-layers", args.colr_v0, "U+0041")
        cangjie_cmd = command(
            args.glyph_bench, case, "cangjie", "color-layers", 64,
            args.iterations, args.samples, args.minimum_target_size,
        )
        freetype_cmd = command(
            args.glyph_bench, case, "freetype", "color-layers", 64,
            args.iterations, args.samples, args.minimum_target_size,
        )
        cangjie_a = run(cangjie_cmd, args.cpu)
        freetype_a = run(freetype_cmd, args.cpu)
        freetype_b = run(freetype_cmd, args.cpu)
        cangjie_b = run(cangjie_cmd, args.cpu)
        for engine, first, second in (
            ("cangjie", cangjie_a, cangjie_b),
            ("freetype", freetype_a, freetype_b),
        ):
            if first.get("checksum") != second.get("checksum"):
                failures.append(
                    f"{case.name}: {engine} checksum "
                    f"{first.get('checksum')}/{second.get('checksum')}"
                )
        if cangjie_a.get("checksum") != freetype_a.get("checksum"):
            failures.append(
                f"{case.name}: cross-engine layers "
                f"{cangjie_a.get('checksum')}/{freetype_a.get('checksum')}"
            )
        cangjie_ns = math.sqrt(
            float(cangjie_a["sample_median_ns_per_iter"])
            * float(cangjie_b["sample_median_ns_per_iter"])
        )
        freetype_ns = math.sqrt(
            float(freetype_a["sample_median_ns_per_iter"])
            * float(freetype_b["sample_median_ns_per_iter"])
        )
        speedup = math.inf if cangjie_ns == 0 else freetype_ns / cangjie_ns
        print(
            f"{case.name}: cangjie={cangjie_ns:.3f}ns "
            f"freetype={freetype_ns:.3f}ns speedup={speedup:.3f}x"
        )
        if args.fail_on_slower and speedup <= 1.0:
            failures.append(
                f"{case.name}: performance "
                f"{cangjie_ns:.3f}ns/{freetype_ns:.3f}ns"
            )
        row_count += 1
    if failures:
        print("Cangjie/FreeType lifecycle matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(f"Cangjie/FreeType lifecycle matrix completed: {row_count} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
