#!/usr/bin/env python3
"""Run a cross-script Cangjie/Parley layout and reflow matrix."""

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
    text: Path
    family: str
    width: str
    fallback_font: Path | None = None


# These rows have byte-addressable geometry and placement parity. Object rows
# intentionally use their separate object-geometry contract, while the other
# Japanese styles retain known line-breaking differences. Keeping this list
# explicit prevents a newly added coverage row from silently becoming a false
# semantic-equivalence claim.
SEMANTIC_EQUALITY_ROWS = frozenset(
    {
        ("latin", "layout", "default"),
        ("latin", "layout", "center"),
        ("latin", "reflow", "center"),
        ("latin", "layout", "spacing"),
        ("latin", "layout", "alternating"),
        ("latin", "reflow", "default"),
        ("arabic", "layout", "default"),
        ("arabic", "layout", "spacing"),
        ("arabic", "layout", "alternating"),
        ("arabic", "reflow", "default"),
        ("mixed-bidi-ltr", "layout", "default"),
        ("mixed-bidi-ltr", "reflow", "default"),
        ("mixed-bidi-rtl", "layout", "default"),
        ("mixed-bidi-rtl", "reflow", "default"),
        ("japanese", "layout", "alternating"),
        ("fallback", "layout", "fallback"),
        ("fallback", "reflow", "fallback"),
    }
)

DEFAULT_MINIMUM_SPEEDUP = 1.01


def valid_minimum_speedup(minimum_speedup: float) -> bool:
    """A benchmark margin must be finite and strictly better than parity."""
    return math.isfinite(minimum_speedup) and minimum_speedup > 1.0


def meets_speedup_gate(speedup: float, minimum_speedup: float) -> bool:
    """Return whether a measured ratio reaches the declared gate boundary."""
    return not math.isnan(speedup) and speedup >= minimum_speedup


def gate_failed(
    speedup: float, minimum_speedup: float, fail_on_slower: bool
) -> bool:
    """Keep threshold reporting independent from opt-in enforcement."""
    return fail_on_slower and not meets_speedup_gate(speedup, minimum_speedup)


def test_speedup_gate_boundary() -> None:
    minimum = DEFAULT_MINIMUM_SPEEDUP
    assert valid_minimum_speedup(minimum)
    assert not valid_minimum_speedup(1.0)
    assert not valid_minimum_speedup(math.inf)
    assert not valid_minimum_speedup(math.nan)
    # An exact minimum is a pass. Testing the adjacent lower float guards
    # against accidentally restoring the old parity-only comparison.
    assert meets_speedup_gate(minimum, minimum)
    assert not meets_speedup_gate(math.nextafter(minimum, -math.inf), minimum)
    assert meets_speedup_gate(math.inf, minimum)
    assert not meets_speedup_gate(math.nan, minimum)
    assert not gate_failed(1.0, minimum, False)
    assert not gate_failed(math.nan, minimum, False)
    assert gate_failed(1.0, minimum, True)
    assert gate_failed(math.nan, minimum, True)
    assert not gate_failed(minimum, minimum, True)
    custom_minimum = 1.125
    assert meets_speedup_gate(custom_minimum, custom_minimum)
    assert not meets_speedup_gate(
        math.nextafter(custom_minimum, -math.inf), custom_minimum
    )


def run(command: list[str], cpu: int | None) -> dict[str, str]:
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr, end="")
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}")
    fields: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", completed.stdout):
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def cangjie_command(
    executable: Path, case: Case, style: str, phase: str, iterations: int, samples: int
) -> list[str]:
    command = [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.width, phase, "auto", style,
    ]
    if case.fallback_font is not None:
        command.append(str(case.fallback_font))
    return command


def parley_command(
    executable: Path, case: Case, style: str, phase: str, iterations: int, samples: int
) -> list[str]:
    command = [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.family, case.width, "auto", style, phase,
    ]
    if case.fallback_font is not None:
        command.append(str(case.fallback_font))
    return command


def main() -> int:
    test_speedup_gate_boundary()
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--parley-manifest", required=True, type=Path)
    parser.add_argument("--parley-root", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--arabic-font", required=True, type=Path)
    parser.add_argument("--japanese-font", required=True, type=Path)
    parser.add_argument(
        "--bidi-font",
        type=Path,
        default=Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        help="font covering the Latin, Arabic, and Hebrew mixed-bidi fixture",
    )
    parser.add_argument(
        "--bidi-family",
        default="DejaVu Sans",
        help="family name registered by --bidi-font in the Parley oracle",
    )
    parser.add_argument(
        "--fallback-font",
        type=Path,
        default=Path("/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf"),
    )
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--cpu", type=int)
    parser.add_argument(
        "--fail-on-slower",
        action="store_true",
        help=(
            "fail when Cangjie does not meet --minimum-speedup in any "
            "matrix row"
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
    for label, path in (
        ("--roboto", args.roboto),
        ("--arabic-font", args.arabic_font),
        ("--japanese-font", args.japanese_font),
        ("--bidi-font", args.bidi_font),
        ("--fallback-font", args.fallback_font),
    ):
        if not path.is_file():
            parser.error(f"{label} does not name a readable font file: {path}")

    gate_mode = "enforced" if args.fail_on_slower else "report-only"
    print(
        f"parley_performance_gate={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )
    # Parley 0.7's public Layout/Builder surface is horizontal-only: it has no
    # writing-mode or vertical-flow input. Keep vertical Cangjie evidence in
    # its conformance suite rather than fabricating a rotated horizontal row.
    parley_vertical_api = False

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.parley_manifest)],
        check=True,
    )
    parley = args.parley_manifest.parent / "target/release/parley-layout-oracle"
    samples_root = args.parley_root / "parley_dev/assets/text_samples"
    cases = (
        Case("latin", args.roboto, samples_root / "latin.txt", "Roboto", "200"),
        Case("arabic", args.arabic_font, samples_root / "arabic.txt", "Noto Kufi Arabic", "180"),
        Case("japanese", args.japanese_font, samples_root / "japanese.txt", "Noto Sans CJK JP", "200"),
        Case(
            "mixed-bidi-ltr",
            args.bidi_font,
            Path("tests/data/parley-mixed-bidi-ltr.txt"),
            args.bidi_family,
            "220",
        ),
        Case(
            "mixed-bidi-rtl",
            args.bidi_font,
            Path("tests/data/parley-mixed-bidi-rtl.txt"),
            args.bidi_family,
            "220",
        ),
        Case(
            "fallback",
            args.roboto,
            Path("tests/data/parley-fallback.txt"),
            "Roboto",
            "200",
            args.fallback_font,
        ),
    )
    center_case = Case(
        "latin",
        args.roboto,
        Path("tests/data/parley-center-latin.txt"),
        "Roboto",
        "200",
    )
    failures: list[str] = []
    for case in cases:
        if case.name == "fallback":
            matrix_rows = [("layout", "fallback"), ("reflow", "fallback")]
        elif case.name.startswith("mixed-bidi-"):
            # Keep this differential focused on the base-direction resolver and
            # visual ordering. Styling and inline-object coverage use fixtures
            # whose source-order contracts are independent of mixed bidi.
            matrix_rows = [("layout", "default"), ("reflow", "default")]
        else:
            matrix_rows = [
                ("layout", "default"),
                ("layout", "spacing"),
                ("layout", "alternating"),
                ("reflow", "default"),
                ("layout", "inline-object"),
                ("reflow", "inline-object"),
                ("layout", "out-of-flow-object"),
                ("reflow", "out-of-flow-object"),
                ("layout", "custom-out-of-flow-object"),
                ("reflow", "custom-out-of-flow-object"),
            ]
            if case.name == "latin":
                matrix_rows.insert(1, ("layout", "center"))
                matrix_rows.insert(2, ("reflow", "center"))
        for phase, style in matrix_rows:
            # Keep centered placement independent from the existing sample's
            # terminal-space policy; the dedicated fixture has visible edges.
            row_case = center_case if style == "center" else case
            cangjie_first = run(
                cangjie_command(args.cangjie, row_case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            parley_first = run(
                parley_command(parley, row_case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            parley_second = run(
                parley_command(parley, row_case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            cangjie_second = run(
                cangjie_command(args.cangjie, row_case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            records = (cangjie_first, parley_first, parley_second, cangjie_second)
            shapes = {
                (
                    item.get("text_bytes"),
                    item.get("glyphs"),
                    item.get("lines"),
                    item.get("objects"),
                )
                for item in records
            }
            if len(shapes) != 1:
                failures.append(f"{case.name}/{phase}/{style}: output counts={sorted(shapes)}")
            expected_objects = "1" if style in (
                "inline-object",
                "out-of-flow-object",
                "custom-out-of-flow-object",
            ) else "0"
            if any(item.get("objects") != expected_objects for item in records):
                failures.append(
                    f"{case.name}/{phase}/{style}: expected objects={expected_objects}, "
                    f"got {[item.get('objects') for item in records]}"
                )
            # Native geometry is normalized to logical lines/graphemes by both
            # oracles. The checksum retains source ranges, visible advances,
            # and line-relative cluster positions; native physical origins and
            # visually discarded trailing whitespace are intentionally absent.
            geometry_checksums = {item.get("geometry_checksum") for item in records}
            geometry_equivalent = len(geometry_checksums) == 1 and None not in geometry_checksums
            placement_checksums = {item.get("placement_checksum") for item in records}
            placement_equivalent = (
                len(placement_checksums) == 1 and None not in placement_checksums
            )
            requires_semantic_equality = (case.name, phase, style) in SEMANTIC_EQUALITY_ROWS
            if requires_semantic_equality and not geometry_equivalent:
                failures.append(
                    f"{case.name}/{phase}/{style}: geometry checksums="
                    f"{[item.get('geometry_checksum') for item in records]}"
                )
            if requires_semantic_equality and not placement_equivalent:
                failures.append(
                    f"{case.name}/{phase}/{style}: placement checksums="
                    f"{[item.get('placement_checksum') for item in records]}"
                )
            object_checksums = {item.get("object_checksum") for item in records}
            object_geometry_equivalent = (
                len(object_checksums) == 1 and None not in object_checksums
            )
            requires_object_geometry = expected_objects == "1"
            if requires_object_geometry and not object_geometry_equivalent:
                failures.append(
                    f"{case.name}/{phase}/{style}: object checksums="
                    f"{[item.get('object_checksum') for item in records]}"
                )
            # Each implementation also hashes its complete native layout. The
            # hash encodings intentionally differ (Cangjie uses FNV-1a over its
            # public layout records; Parley uses FNV-1a over line/glyph fields),
            # so cross-engine equality is not meaningful. Requiring stable,
            # non-zero hashes across both symmetric runs still prevents a count-
            # equivalent but internally unstable layout from passing this gate.
            for engine, first, second in (
                ("cangjie", cangjie_first, cangjie_second),
                ("parley", parley_first, parley_second),
            ):
                first_checksum = first.get("checksum")
                second_checksum = second.get("checksum")
                if (
                    first_checksum is None
                    or second_checksum is None
                    or first_checksum == "0000000000000000"
                    or first_checksum != second_checksum
                ):
                    failures.append(
                        f"{case.name}/{phase}/{style}: {engine} checksum="
                        f"{first_checksum!r}/{second_checksum!r}"
                    )
            cangjie_a = float(cangjie_first["median_ns_per_iter"])
            cangjie_b = float(cangjie_second["median_ns_per_iter"])
            parley_a = float(parley_first["median_ns_per_iter"])
            parley_b = float(parley_second["median_ns_per_iter"])
            cangjie_ns = math.sqrt(cangjie_a * cangjie_b)
            parley_ns = math.sqrt(parley_a * parley_b)
            speedup = math.inf if cangjie_ns == 0 else parley_ns / cangjie_ns
            threshold_result = (
                "met"
                if meets_speedup_gate(speedup, args.minimum_speedup)
                else "below-minimum"
            )
            if gate_failed(speedup, args.minimum_speedup, args.fail_on_slower):
                failures.append(
                    f"{case.name}/{phase}/{style}: speedup {speedup:.6f}x "
                    f"is below the {args.minimum_speedup:.6f}x minimum"
                )
            print(
                f"{case.name}/{phase}/{style}: "
                f"cangjie_ns={cangjie_a:.3f}/{cangjie_b:.3f} "
                f"parley_ns={parley_a:.3f}/{parley_b:.3f} "
                f"speedup={speedup:.6f}x "
                f"minimum_speedup={args.minimum_speedup:.6f}x "
                f"threshold={threshold_result} gate_mode={gate_mode} "
                f"glyphs={cangjie_first.get('glyphs')} "
                f"lines={cangjie_first.get('lines')} "
                f"objects={cangjie_first.get('objects')} "
                f"geometry_equal={str(geometry_equivalent).lower()} "
                f"placement_equal="
                f"{str(placement_equivalent).lower() if requires_semantic_equality else 'n/a'} "
                f"object_geometry_equal="
                f"{str(object_geometry_equivalent).lower() if requires_object_geometry else 'n/a'}"
            )
    if failures:
        print(
            "Cangjie/Parley matrix failed "
            f"(minimum_speedup={args.minimum_speedup:.6f}x):",
            file=sys.stderr,
        )
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(
        "Cangjie/Parley output-count, proven text-semantics, and object-geometry "
        f"matrix passed: 38 cases gate_mode={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )
    print(f"parley_vertical_api={str(parley_vertical_api).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
