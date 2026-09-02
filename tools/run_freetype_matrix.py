#!/usr/bin/env python3
"""Run a symmetric Cangjie/FreeType raster and bitmap lifecycle matrix."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


DEFAULT_MINIMUM_SPEEDUP = 1.01
TOOL_NAME = "run_freetype_matrix.py"
TOOL_VERSION = "1.0"
REPORT_SCHEMA_VERSION = 1


def valid_minimum_speedup(minimum_speedup: float) -> bool:
    """A strict performance margin must be finite and exceed parity."""
    return math.isfinite(minimum_speedup) and minimum_speedup > 1.0


def meets_speedup_gate(speedup: float, minimum_speedup: float) -> bool:
    """Treat the declared boundary itself as a passing measurement."""
    return not math.isnan(speedup) and speedup >= minimum_speedup


@dataclass(frozen=True)
class Case:
    name: str
    font: Path
    codepoint: str


@dataclass(frozen=True)
class RowResult:
    name: str
    case: Case
    mode: str
    size: int
    target_size: int
    cangjie_checksum_a: str | None
    cangjie_checksum_b: str | None
    reference_checksum_a: str | None
    reference_checksum_b: str | None
    semantic_agreement: bool
    cangjie_first_ns_per_iter: float
    cangjie_second_ns_per_iter: float
    reference_first_ns_per_iter: float
    reference_second_ns_per_iter: float
    speedup: float
    threshold_status: str

    @property
    def cangjie_geometric_mean_ns_per_iter(self) -> float:
        """Return the A/B aggregate used for the row's speedup."""
        return math.sqrt(
            self.cangjie_first_ns_per_iter * self.cangjie_second_ns_per_iter
        )

    @property
    def reference_geometric_mean_ns_per_iter(self) -> float:
        """Return the reference A/B aggregate used for the row's speedup."""
        return math.sqrt(
            self.reference_first_ns_per_iter * self.reference_second_ns_per_iter
        )


@dataclass(frozen=True)
class RunConfiguration:
    glyph_bench: Path
    roboto: Path
    cff: Path
    cff2: Path
    arabic: Path
    cjk: Path
    cbdt: Path | None
    sbix: Path | None
    colr_v0: Path | None
    iterations: int
    samples: int
    cpu: int | None
    sizes: tuple[int, ...]
    minimum_target_size: int
    fail_on_slower: bool
    minimum_speedup: float


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


def case_result_json(result: RowResult) -> dict[str, Any]:
    return {
        "name": result.name,
        "font": str(result.case.font),
        "codepoint": result.case.codepoint,
        "mode": result.mode,
        "size": result.size,
        "target_size": result.target_size,
        "semantic": {
            "cangjie_checksums": {
                "a": result.cangjie_checksum_a,
                "b": result.cangjie_checksum_b,
            },
            "reference_checksums": {
                "a": result.reference_checksum_a,
                "b": result.reference_checksum_b,
            },
            "agreement": result.semantic_agreement,
        },
        "timing": {
            "cangjie_ns_per_iter": {
                "a": result.cangjie_first_ns_per_iter,
                "b": result.cangjie_second_ns_per_iter,
            },
            "reference_ns_per_iter": {
                "a": result.reference_first_ns_per_iter,
                "b": result.reference_second_ns_per_iter,
            },
            "speedup": result.speedup,
        },
        "threshold_status": result.threshold_status,
    }


def build_json_report(
    configuration: RunConfiguration,
    manifest: Sequence[str],
    results: Sequence[RowResult],
) -> dict[str, Any]:
    if len(results) != len(manifest):
        raise ValueError(
            "cannot build a completed report from a partial matrix: "
            f"expected {len(manifest)} rows, got {len(results)}"
        )
    actual_names = [result.name for result in results]
    if actual_names != list(manifest):
        raise ValueError(
            "cannot build report from reordered or mismatched rows: "
            f"expected {list(manifest)}, got {actual_names}"
        )
    below_minimum = [
        result.name for result in results if result.threshold_status != "met"
    ]
    semantic_failures = [
        result.name for result in results if not result.semantic_agreement
    ]
    gate_mode = "enforced" if configuration.fail_on_slower else "report-only"
    thresholds_met = not below_minimum
    semantic_agreement = not semantic_failures
    command_succeeded = semantic_agreement and (
        thresholds_met or not configuration.fail_on_slower
    )
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "tool": {"name": TOOL_NAME, "version": TOOL_VERSION},
        "run": {
            "glyph_bench": str(configuration.glyph_bench),
            "roboto": str(configuration.roboto),
            "cff": str(configuration.cff),
            "cff2": str(configuration.cff2),
            "arabic": str(configuration.arabic),
            "cjk": str(configuration.cjk),
            "cbdt": None if configuration.cbdt is None else str(configuration.cbdt),
            "sbix": None if configuration.sbix is None else str(configuration.sbix),
            "colr_v0": (
                None if configuration.colr_v0 is None else str(configuration.colr_v0)
            ),
            "iterations": configuration.iterations,
            "samples": configuration.samples,
            "cpu": configuration.cpu,
            "sizes": list(configuration.sizes),
            "minimum_target_size": configuration.minimum_target_size,
            "fail_on_slower": configuration.fail_on_slower,
            "minimum_speedup": configuration.minimum_speedup,
        },
        "gate": {
            "mode": gate_mode,
            "minimum_speedup": configuration.minimum_speedup,
            "thresholds_met": thresholds_met,
            "semantic_agreement": semantic_agreement,
            "command_succeeded": command_succeeded,
        },
        "manifest": {
            "expected_row_count": len(manifest),
            "actual_row_count": len(results),
            "rows": list(manifest),
        },
        "rows": [case_result_json(result) for result in results],
        "summary": {
            "row_count": len(results),
            "thresholds_met_count": len(results) - len(below_minimum),
            "below_minimum_count": len(below_minimum),
            "below_minimum_rows": below_minimum,
            "semantic_agreement_count": len(results) - len(semantic_failures),
            "semantic_failure_count": len(semantic_failures),
            "semantic_failure_rows": semantic_failures,
        },
    }


def write_json_atomic(path: Path, report: Mapping[str, Any]) -> None:
    parent = path.parent
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            dir=parent, prefix=f".{path.name}.", suffix=".tmp", text=True
        )
    except OSError as error:
        raise RuntimeError(
            f"cannot create JSON output for {path}: {error}"
        ) from error
    descriptor_open = True
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            descriptor_open = False
            json.dump(report, output, indent=2, sort_keys=True, allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        if descriptor_open:
            os.close(descriptor)
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def emit_json_report(
    path: Path | None,
    configuration: RunConfiguration,
    manifest: Sequence[str],
    results: Sequence[RowResult],
) -> None:
    if path is None:
        return
    write_json_atomic(path, build_json_report(configuration, manifest, results))


def format_row_stdout(result: RowResult, minimum_speedup: float) -> str:
    """Render the stable human summary from the A/B/B/A aggregates.

    The JSON report retains each timing endpoint for auditability. The concise
    stdout contract instead reports the geometric means whose ratio is the
    displayed speedup, so all three human-readable values describe the same
    measurement.
    """
    return (
        f"{result.name}: "
        f"cangjie={result.cangjie_geometric_mean_ns_per_iter:.3f}ns "
        f"freetype={result.reference_geometric_mean_ns_per_iter:.3f}ns "
        f"speedup={result.speedup:.3f}x "
        f"minimum_speedup={minimum_speedup:.3f}x"
    )


def measure_row(
    *,
    name: str,
    case: Case,
    mode: str,
    size: int,
    target_size: int,
    cangjie_a: dict[str, str],
    freetype_a: dict[str, str],
    freetype_b: dict[str, str],
    cangjie_b: dict[str, str],
    compare_cross_engine: bool,
    failures: list[str],
    minimum_speedup: float,
) -> RowResult:
    cangjie_checksum_a = cangjie_a.get("checksum")
    cangjie_checksum_b = cangjie_b.get("checksum")
    reference_checksum_a = freetype_a.get("checksum")
    reference_checksum_b = freetype_b.get("checksum")
    semantic_agreement = True
    if cangjie_checksum_a != cangjie_checksum_b:
        failures.append(
            f"{name}: cangjie checksum {cangjie_checksum_a}/{cangjie_checksum_b}"
        )
        semantic_agreement = False
    if reference_checksum_a != reference_checksum_b:
        failures.append(
            f"{name}: freetype checksum {reference_checksum_a}/{reference_checksum_b}"
        )
        semantic_agreement = False
    if compare_cross_engine and cangjie_checksum_a != reference_checksum_a:
        failures.append(
            f"{name}: cross-engine "
            f"{cangjie_checksum_a}/{reference_checksum_a}"
        )
        semantic_agreement = False
    cangjie_first_ns = float(cangjie_a["sample_median_ns_per_iter"])
    cangjie_second_ns = float(cangjie_b["sample_median_ns_per_iter"])
    reference_first_ns = float(freetype_a["sample_median_ns_per_iter"])
    reference_second_ns = float(freetype_b["sample_median_ns_per_iter"])
    cangjie_mean = math.sqrt(cangjie_first_ns * cangjie_second_ns)
    reference_mean = math.sqrt(reference_first_ns * reference_second_ns)
    speedup = math.inf if cangjie_mean == 0 else reference_mean / cangjie_mean
    threshold_status = (
        "met"
        if meets_speedup_gate(speedup, minimum_speedup)
        else "below-minimum"
    )
    return RowResult(
        name=name,
        case=case,
        mode=mode,
        size=size,
        target_size=target_size,
        cangjie_checksum_a=cangjie_checksum_a,
        cangjie_checksum_b=cangjie_checksum_b,
        reference_checksum_a=reference_checksum_a,
        reference_checksum_b=reference_checksum_b,
        semantic_agreement=semantic_agreement,
        cangjie_first_ns_per_iter=cangjie_first_ns,
        cangjie_second_ns_per_iter=cangjie_second_ns,
        reference_first_ns_per_iter=reference_first_ns,
        reference_second_ns_per_iter=reference_second_ns,
        speedup=speedup,
        threshold_status=threshold_status,
    )


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
        "--json-output",
        type=Path,
        help=(
            "atomically write a versioned JSON artifact after every "
            "successful completed matrix, including report-only runs with "
            "rows below the threshold"
        ),
    )
    parser.add_argument(
        "--fail-on-slower",
        action="store_true",
        help=(
            "fail when Cangjie does not meet --minimum-speedup in any "
            "measured lifecycle row"
        ),
    )
    parser.add_argument(
        "--minimum-speedup",
        type=float,
        default=DEFAULT_MINIMUM_SPEEDUP,
        help=(
            "minimum ratio required by --fail-on-slower "
            f"(default: {DEFAULT_MINIMUM_SPEEDUP:g}); also reported when "
            "the gate is disabled"
        ),
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
    if not valid_minimum_speedup(args.minimum_speedup):
        parser.error("--minimum-speedup must be finite and greater than 1")
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
    manifest: list[str] = []
    rows: list[RowResult] = []
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
        row_name = f"{case.name}/face-open"
        manifest.append(row_name)
        row = measure_row(
            name=row_name,
            case=case,
            mode="face-open",
            size=16,
            target_size=args.minimum_target_size,
            cangjie_a=cangjie_a,
            freetype_a=freetype_a,
            freetype_b=freetype_b,
            cangjie_b=cangjie_b,
            compare_cross_engine=True,
            failures=failures,
            minimum_speedup=args.minimum_speedup,
        )
        rows.append(row)
        print(format_row_stdout(row, args.minimum_speedup))
        if args.fail_on_slower and row.threshold_status != "met":
            failures.append(
                f"{row_name}: performance "
                f"{row.cangjie_geometric_mean_ns_per_iter:.3f}ns/"
                f"{row.reference_geometric_mean_ns_per_iter:.3f}ns"
            )
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
                row_name = f"{case.name}/{mode}/{size}px"
                manifest.append(row_name)
                row = measure_row(
                    name=row_name,
                    case=case,
                    mode=mode,
                    size=size,
                    target_size=target_size,
                    cangjie_a=cangjie_a,
                    freetype_a=freetype_a,
                    freetype_b=freetype_b,
                    cangjie_b=cangjie_b,
                    compare_cross_engine=False,
                    failures=failures,
                    minimum_speedup=args.minimum_speedup,
                )
                rows.append(row)
                print(format_row_stdout(row, args.minimum_speedup))
                if args.fail_on_slower and row.threshold_status != "met":
                    failures.append(
                        f"{row_name}: performance "
                        f"{row.cangjie_geometric_mean_ns_per_iter:.3f}ns/"
                        f"{row.reference_geometric_mean_ns_per_iter:.3f}ns"
                    )
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
            row_name = f"{case.name}/bitmap-render/{size}px"
            manifest.append(row_name)
            row = measure_row(
                name=row_name,
                case=case,
                mode="bitmap-render",
                size=size,
                target_size=args.minimum_target_size,
                cangjie_a=cangjie_a,
                freetype_a=freetype_a,
                freetype_b=freetype_b,
                cangjie_b=cangjie_b,
                compare_cross_engine=True,
                failures=failures,
                minimum_speedup=args.minimum_speedup,
            )
            rows.append(row)
            print(format_row_stdout(row, args.minimum_speedup))
            if args.fail_on_slower and row.threshold_status != "met":
                failures.append(
                    f"{row_name}: performance "
                    f"{row.cangjie_geometric_mean_ns_per_iter:.3f}ns/"
                    f"{row.reference_geometric_mean_ns_per_iter:.3f}ns"
                )
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
        row_name = case.name
        manifest.append(row_name)
        row = measure_row(
            name=row_name,
            case=case,
            mode="color-layers",
            size=64,
            target_size=args.minimum_target_size,
            cangjie_a=cangjie_a,
            freetype_a=freetype_a,
            freetype_b=freetype_b,
            cangjie_b=cangjie_b,
            compare_cross_engine=True,
            failures=failures,
            minimum_speedup=args.minimum_speedup,
        )
        rows.append(row)
        print(format_row_stdout(row, args.minimum_speedup))
        if args.fail_on_slower and row.threshold_status != "met":
            failures.append(
                f"{row_name}: performance "
                f"{row.cangjie_geometric_mean_ns_per_iter:.3f}ns/"
                f"{row.reference_geometric_mean_ns_per_iter:.3f}ns"
            )
    if failures:
        print("Cangjie/FreeType lifecycle matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    emit_json_report(
        args.json_output,
        RunConfiguration(
            glyph_bench=args.glyph_bench,
            roboto=args.roboto,
            cff=args.cff,
            cff2=args.cff2,
            arabic=args.arabic,
            cjk=args.cjk,
            cbdt=args.cbdt,
            sbix=args.sbix,
            colr_v0=args.colr_v0,
            iterations=args.iterations,
            samples=args.samples,
            cpu=args.cpu,
            sizes=sizes,
            minimum_target_size=args.minimum_target_size,
            fail_on_slower=args.fail_on_slower,
            minimum_speedup=args.minimum_speedup,
        ),
        manifest,
        rows,
    )
    print(f"Cangjie/FreeType lifecycle matrix completed: {len(rows)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
