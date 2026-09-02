#!/usr/bin/env python3
"""Run the maintained Cangjie/Skrifa metadata and outline matrix.

The runner intentionally keeps semantic assertions separate from performance
ratios. It checks fields whose representations are shared by both CLIs, while
timings remain independently consumed observations suitable for fixed-CPU
A/B/B/A measurements.
"""

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
from enum import Enum
from pathlib import Path
from typing import Any, Mapping, Sequence


DEFAULT_MINIMUM_SPEEDUP = 1.01
TOOL_NAME = "run_fontations_matrix.py"
TOOL_VERSION = "1.0"
REPORT_SCHEMA_VERSION = 1


def valid_minimum_speedup(minimum_speedup: float) -> bool:
    """A strict performance margin must be finite and exceed parity."""
    return math.isfinite(minimum_speedup) and minimum_speedup > 1.0


def meets_speedup_gate(speedup: float, minimum_speedup: float) -> bool:
    """Treat the declared boundary itself as a passing measurement."""
    return not math.isnan(speedup) and speedup >= minimum_speedup


class FontSource(Enum):
    """Select the physical input independently of its outline format."""

    GENERATED = "generated"
    CFF2 = "cff2"
    VARC = "varc"
    DIRECT = "direct"


@dataclass(frozen=True)
class Case:
    name: str
    mode: str
    font: str
    operand: int
    compare_checksum: bool = True
    font_size: str | None = None
    source: FontSource = FontSource.GENERATED
    variation: str | None = None


@dataclass(frozen=True)
class OutlineCorpus:
    name: str
    font: Path
    glyph_ids: tuple[int, ...]


@dataclass(frozen=True)
class RowResult:
    case: Case
    resolved_font: Path
    semantic_cangjie_checksum: str | None
    semantic_reference_checksum: str | None
    semantic_agreement: bool
    cangjie_first_ns_per_iter: float
    cangjie_second_ns_per_iter: float
    reference_first_ns_per_iter: float
    reference_second_ns_per_iter: float
    speedup: float
    threshold_status: str


@dataclass(frozen=True)
class RunConfiguration:
    cangjie: Path
    skrifa_manifest: Path
    skrifa_executable: Path
    fixture_dir: Path
    roboto: Path
    cff2: Path
    varc: Path
    cff2_extended: Path
    extended: bool
    source: str
    iterations: int
    samples: int
    cpu: int | None
    fail_on_slower: bool
    minimum_speedup: float


EXTENDED_OUTLINE_MODES = ("outline-session", "outline-reuse")
EXTENDED_GLYPHS_PER_CORPUS = 10
EXTENDED_CORPUS_COUNT = 5
PRODUCTION_CASE_COUNT = 5


def expected_row_count(*, source: str, extended: bool) -> int:
    """Return the matrix cardinality implied by the current row manifest."""
    if source == "varc":
        return sum(case.source is FontSource.VARC for case in CASES)
    base = len(CASES) + PRODUCTION_CASE_COUNT
    if not extended:
        return base
    return base + (
        EXTENDED_CORPUS_COUNT
        * EXTENDED_GLYPHS_PER_CORPUS
        * len(EXTENDED_OUTLINE_MODES)
    )


CASES = (
    Case("attributes-head", "attributes", "attributes-head.ttf", 0),
    Case("attributes-os2", "attributes", "attributes-os2.ttf", 0),
    Case("variations", "variations", "variations.ttf", 0),
    Case("palettes", "palettes", "palettes.ttf", 0),
    Case("strikes", "strikes", "strikes.ttf", 0),
    Case("color-v0", "color-glyph", "color-glyph-v0.ttf", 1),
    Case("color-v1", "color-glyph", "color-glyph-v1.ttf", 1),
    Case("glyph-name-post", "glyph-name", "post.ttf", 1),
    Case("glyph-name-cff", "glyph-name", "cff.otf", 1),
    Case("glyph-name-synthetic", "glyph-name", "synthesized.ttf", 1),
    Case("bitmap", "bitmap", "strikes.ttf", 1, True, "16"),
    # Both outline CLIs now run the same FNV command-stream consumer. Metadata
    # lives in dedicated matrix rows so decode timing does not charge work to
    # only one engine.
    Case("outline-glyf", "outline-session", "synthesized.ttf", 1),
    # Skrifa's public draw takes a caller pen and reuses its parsed glyph; this
    # row compares that lifecycle with Cangjie's explicit caller-owned output.
    # Keep the owning outline row above so reuse cannot silently redefine it.
    Case("outline-glyf-reuse", "outline-reuse", "synthesized.ttf", 1),
    Case("outline-cff", "outline-session", "cff.otf", 1),
    # CFF2 has a distinct INDEX/DICT/variation-aware execution model. The
    # retained upstream Cantarell subset also exercises real variable-CFF2
    # data that both engines accept, unlike Cangjie's parser-only fixtures.
    Case(
        "outline-cff2", "outline-session", "Cantarell-VF-ABC.otf",
        1, source=FontSource.CFF2,
    ),
    Case(
        "outline-cff2-reuse", "outline-reuse", "Cantarell-VF-ABC.otf",
        1, source=FontSource.CFF2,
    ),
    Case(
        "outline-cff2-var-max", "outline-session",
        "Cantarell-VF-ABC.otf", 1, source=FontSource.CFF2, variation="1",
    ),
    Case(
        "outline-cff2-var-min", "outline-session",
        "Cantarell-VF-ABC.otf", 1, source=FontSource.CFF2, variation="-1",
    ),
    Case(
        "outline-cff2-var-max-reuse", "outline-reuse",
        "Cantarell-VF-ABC.otf", 1, source=FontSource.CFF2, variation="1",
    ),
    Case(
        "outline-cff2-var-min-reuse", "outline-reuse",
        "Cantarell-VF-ABC.otf", 1, source=FontSource.CFF2, variation="-1",
    ),
    # This compact upstream font covers nested VARC components, component
    # axis overrides, and the 0.5 conditional boundary. Keep both owning and
    # caller-storage lifecycles so reuse cannot substitute for materialization.
    Case(
        "outline-varc-default", "outline-session",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
    ),
    Case(
        "outline-varc-default-reuse", "outline-reuse",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
    ),
    Case(
        "outline-varc-049", "outline-session",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
        variation="0.49,0",
    ),
    Case(
        "outline-varc-049-reuse", "outline-reuse",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
        variation="0.49,0",
    ),
    Case(
        "outline-varc-050", "outline-session",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
        variation="0.5,0",
    ),
    Case(
        "outline-varc-050-reuse", "outline-reuse",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
        variation="0.5,0",
    ),
    Case(
        "outline-varc-max", "outline-session",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
        variation="1,0",
    ),
    Case(
        "outline-varc-max-reuse", "outline-reuse",
        "varc-ac01-conditional.ttf", 1, source=FontSource.VARC,
        variation="1,0",
    ),
)


def case_font(case: Case, args: argparse.Namespace) -> Path:
    """Resolve maintained inputs without overloading one external font path."""
    if case.source is FontSource.GENERATED:
        return args.fixture_dir / case.font
    if case.source is FontSource.CFF2:
        return args.cff2
    if case.source is FontSource.VARC:
        return args.varc
    raise ValueError(f"{case.name}: direct font source requires an explicit path")


def parse_fields(output: str) -> dict[str, str]:
    normalized = output.replace("\\t", "\t")
    lines = [line for line in normalized.splitlines() if line]
    # Cangjie's TSV is a header/data pair; Skrifa emits key=value tokens.
    for index in range(len(lines) - 1):
        header = lines[index].split("\t")
        values = lines[index + 1].split("\t")
        if "checksum" in header and len(header) == len(values):
            return dict(zip(header, values))
    result: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", normalized):
        if "=" in token:
            key, value = token.split("=", 1)
            result[key] = value
    return result


def run(command: list[str], cpu: int | None) -> dict[str, str]:
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr, end="")
        print(completed.stderr, file=sys.stderr, end="")
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}")
    return parse_fields(completed.stdout + completed.stderr)


def case_result_json(result: RowResult) -> dict[str, Any]:
    return {
        "name": result.case.name,
        "mode": result.case.mode,
        "font": str(result.resolved_font),
        "operand": result.case.operand,
        "font_size": result.case.font_size,
        "variation": result.case.variation,
        "source": result.case.source.value,
        "semantic": {
            "cangjie_checksum": result.semantic_cangjie_checksum,
            "reference_checksum": result.semantic_reference_checksum,
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
    manifest: Sequence[Case],
    results: Sequence[RowResult],
) -> dict[str, Any]:
    if len(results) != len(manifest):
        raise ValueError(
            "cannot build a completed report from a partial matrix: "
            f"expected {len(manifest)} rows, got {len(results)}"
        )
    expected_names = [case.name for case in manifest]
    actual_names = [result.case.name for result in results]
    if actual_names != expected_names:
        raise ValueError(
            "cannot build report from reordered or mismatched rows: "
            f"expected {expected_names}, got {actual_names}"
        )
    below_minimum = [
        result.case.name
        for result in results
        if result.threshold_status != "met"
    ]
    semantic_failures = [
        result.case.name
        for result in results
        if not result.semantic_agreement
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
            "cangjie_executable": str(configuration.cangjie),
            "skrifa_manifest": str(configuration.skrifa_manifest),
            "skrifa_executable": str(configuration.skrifa_executable),
            "fixture_dir": str(configuration.fixture_dir),
            "roboto": str(configuration.roboto),
            "cff2": str(configuration.cff2),
            "varc": str(configuration.varc),
            "cff2_extended": str(configuration.cff2_extended),
            "extended": configuration.extended,
            "source": configuration.source,
            "iterations": configuration.iterations,
            "samples": configuration.samples,
            "cpu": configuration.cpu,
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
            "rows": expected_names,
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
    manifest: Sequence[Case],
    results: Sequence[RowResult],
) -> None:
    if path is None:
        return
    write_json_atomic(path, build_json_report(configuration, manifest, results))


def cangjie_command(
    executable: Path,
    case: Case,
    font: Path,
    iterations: int,
    samples: int,
) -> list[str]:
    command = [
        str(executable), "--engine", "cangjie", "--mode", case.mode,
        "--font", str(font), "--glyph-id", str(case.operand),
        "--codepoint", f"U+{case.operand:X}", "--iterations",
        str(iterations), "--warmup", "3", "--samples", str(samples),
    ]
    if case.font_size is not None:
        command.extend(("--font-size", case.font_size))
    if case.variation is not None:
        command.extend(("--variation", case.variation))
    return command


def skrifa_command(
    executable: Path,
    case: Case,
    font: Path,
    iterations: int,
    samples: int,
) -> list[str]:
    mode = {
        "bitmap": "bitmap-summary",
        "outline-session": "outline",
        "outline-reuse": "outline-reuse",
    }.get(case.mode, case.mode)
    if case.variation is not None and mode == "outline":
        mode = "outline-at"
    elif case.variation is not None and mode == "outline-reuse":
        mode = "outline-reuse-at"
    command = [str(executable), str(font), mode, str(case.operand)]
    if case.font_size is not None:
        command.append(case.font_size)
    if case.variation is not None:
        command.append(case.variation)
    command.extend((str(iterations), str(samples)))
    return command


def measure_case(
    *,
    args: argparse.Namespace,
    cangjie: Path,
    skrifa: Path,
    case: Case,
    font: Path,
    failures: list[str],
) -> RowResult:
    cangjie_semantic = run(
        cangjie_command(cangjie, case, font, 1, 1), args.cpu
    )
    reference_semantic = run(
        skrifa_command(skrifa, case, font, 1, 1), args.cpu
    )
    semantic_cangjie_checksum = cangjie_semantic.get("checksum")
    semantic_reference_checksum = reference_semantic.get("checksum")
    semantic_agreement = (
        not case.compare_checksum
        or (
            semantic_cangjie_checksum is not None
            and semantic_reference_checksum is not None
            and int(semantic_cangjie_checksum, 16)
            == int(semantic_reference_checksum, 16)
        )
    )
    if not semantic_agreement:
        failures.append(
            f"{case.name}: checksum: Cangjie={semantic_cangjie_checksum!r}, "
            f"Skrifa={semantic_reference_checksum!r}"
        )
    cangjie_first = (
        cangjie_semantic if args.iterations == 1 and args.samples == 1 else run(
            cangjie_command(cangjie, case, font, args.iterations, args.samples),
            args.cpu,
        )
    )
    reference_first = (
        reference_semantic if args.iterations == 1 and args.samples == 1 else run(
            skrifa_command(skrifa, case, font, args.iterations, args.samples),
            args.cpu,
        )
    )
    reference_second = run(
        skrifa_command(skrifa, case, font, args.iterations, args.samples),
        args.cpu,
    )
    cangjie_second = run(
        cangjie_command(cangjie, case, font, args.iterations, args.samples),
        args.cpu,
    )
    cangjie_first_ns = float(cangjie_first["sample_median_ns_per_iter"])
    cangjie_second_ns = float(cangjie_second["sample_median_ns_per_iter"])
    reference_first_ns = float(reference_first["median_ns_per_iter"])
    reference_second_ns = float(reference_second["median_ns_per_iter"])
    cangjie_mean = math.sqrt(cangjie_first_ns * cangjie_second_ns)
    reference_mean = math.sqrt(reference_first_ns * reference_second_ns)
    speedup = math.inf if cangjie_mean == 0 else reference_mean / cangjie_mean
    threshold_status = (
        "met"
        if meets_speedup_gate(speedup, args.minimum_speedup)
        else "below-minimum"
    )
    return RowResult(
        case=case,
        resolved_font=font,
        semantic_cangjie_checksum=semantic_cangjie_checksum,
        semantic_reference_checksum=semantic_reference_checksum,
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
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--skrifa-manifest", required=True, type=Path)
    parser.add_argument("--fixture-dir", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--cff2", required=True, type=Path)
    parser.add_argument("--varc", required=True, type=Path)
    parser.add_argument(
        "--cff2-extended",
        type=Path,
        default=Path("/home/passchaos/Work/fontations/skera/test-data/fonts/AdobeVFPrototype.otf"),
        help="larger production CFF2 variable font for --extended",
    )
    parser.add_argument(
        "--extended", action="store_true",
        help="include broader production-font outline differentials",
    )
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--cpu", type=int)
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
        "--source", choices=("all", "varc"), default="all",
        help="run every maintained source or only the retained VARC rows",
    )
    parser.add_argument(
        "--fail-on-slower", action="store_true",
        help=(
            "fail when any measured Cangjie row does not meet "
            "--minimum-speedup"
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
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    if not valid_minimum_speedup(args.minimum_speedup):
        parser.error("--minimum-speedup must be finite and greater than 1")

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.skrifa_manifest)],
        check=True,
    )
    skrifa = args.skrifa_manifest.parent / "target/release/fontations-bitmap-oracle"
    failures: list[str] = []
    rows: list[RowResult] = []
    manifest = list(CASES if args.source == "all" else tuple(
        case for case in CASES if case.source is FontSource.VARC
    ))
    for case in manifest:
        rows.append(
            measure_case(
                args=args,
                cangjie=args.cangjie,
                skrifa=skrifa,
                case=case,
                font=case_font(case, args),
                failures=failures,
            )
        )

    if args.extended and args.source == "all":
        corpora = (
            OutlineCorpus(
                "roboto-glyf", args.roboto,
                (1, 2, 3, 10, 20, 38, 64, 96, 128, 192),
            ),
            OutlineCorpus(
                "dejavu-glyf",
                Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
                (1, 36, 59, 97, 116, 132, 133, 171, 256, 5926),
            ),
            OutlineCorpus(
                "noto-arabic-glyf",
                Path("/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf"),
                (1, 2, 3, 10, 20, 50, 100, 200, 400, 600),
            ),
            OutlineCorpus(
                "stix-cff",
                Path("/usr/share/fonts/opentype/stix/STIXGeneral-Regular.otf"),
                (1, 2, 3, 10, 20, 36, 64, 96, 128, 192),
            ),
            OutlineCorpus(
                "adobe-cff2", args.cff2_extended,
                # These glyphs have byte-identical command streams in both
                # decoders. The explicit-closing-line cases are retained here
                # because they previously exposed a command-stream mismatch.
                # The CFF2 stack now uses the format's 513-entry limit, so glyph
                # 2's large blend program is covered alongside closing-line cases.
                (1, 2, 3, 10, 20, 36, 64, 96, 128, 192),
            ),
        )
        for corpus in corpora:
            if not corpus.font.is_file():
                failures.append(f"{corpus.name}: missing font {corpus.font}")
                continue
            for glyph_id in corpus.glyph_ids:
                for mode in EXTENDED_OUTLINE_MODES:
                    case = Case(
                        f"{corpus.name}-gid{glyph_id}-{mode}",
                        mode, corpus.font.name, glyph_id,
                        source=FontSource.DIRECT,
                    )
                    manifest.append(case)
                    rows.append(
                        measure_case(
                            args=args,
                            cangjie=args.cangjie,
                            skrifa=skrifa,
                            case=case,
                            font=corpus.font,
                            failures=failures,
                        )
                    )

    # Production-font queries cover the immutable cmap, metrics, bounds, and
    # complete global-metrics paths that synthetic fixtures cannot represent.
    roboto = Path(args.roboto)
    production_cases = list((
        Case("family-name", "family-name", roboto.name, 0),
        Case("charmap", "charmap", roboto.name, ord("A")),
        Case("metrics", "metrics", roboto.name, 38),
        Case("bounds", "bounds", roboto.name, 38),
        Case("global-metrics", "global-metrics", roboto.name, 0),
    ) if args.source == "all" else [])
    manifest.extend(production_cases)
    for case in production_cases:
        rows.append(
            measure_case(
                args=args,
                cangjie=args.cangjie,
                skrifa=skrifa,
                case=case,
                font=roboto,
                failures=failures,
            )
        )

    if len(rows) != len(manifest):
        failures.append(
            "matrix row manifest mismatch: "
            f"expected={len(manifest)} measured={len(rows)}"
        )

    for row in rows:
        cangjie_mean = math.sqrt(
            row.cangjie_first_ns_per_iter * row.cangjie_second_ns_per_iter
        )
        reference_mean = math.sqrt(
            row.reference_first_ns_per_iter * row.reference_second_ns_per_iter
        )
        print(
            f"{row.case.name}: "
            f"cangjie_ns={row.cangjie_first_ns_per_iter:.3f}/"
            f"{row.cangjie_second_ns_per_iter:.3f} "
            f"skrifa_ns={row.reference_first_ns_per_iter:.3f}/"
            f"{row.reference_second_ns_per_iter:.3f} "
            f"speedup={row.speedup:.3f}x "
            f"minimum_speedup={args.minimum_speedup:.3f}x"
        )
        if (args.fail_on_slower and
                row.threshold_status != "met"):
            failures.append(
                f"{row.case.name}: performance Cangjie={cangjie_mean:.3f}ns/"
                f"Skrifa={reference_mean:.3f}ns"
            )
    if failures:
        print("Fontations/Skrifa semantic matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    emit_json_report(
        args.json_output,
        RunConfiguration(
            cangjie=args.cangjie,
            skrifa_manifest=args.skrifa_manifest,
            skrifa_executable=skrifa,
            fixture_dir=args.fixture_dir,
            roboto=args.roboto,
            cff2=args.cff2,
            varc=args.varc,
            cff2_extended=args.cff2_extended,
            extended=args.extended,
            source=args.source,
            iterations=args.iterations,
            samples=args.samples,
            cpu=args.cpu,
            fail_on_slower=args.fail_on_slower,
            minimum_speedup=args.minimum_speedup,
        ),
        manifest,
        rows,
    )
    print(f"Fontations/Skrifa matrix passed: {len(rows)} cases")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    # Parsed by main's complete parser; this lightweight pre-read keeps mypy
    # and linters from treating the injected build argument as undeclared.
    sys.exit(main())
