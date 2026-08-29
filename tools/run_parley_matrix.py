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
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--parley-manifest", required=True, type=Path)
    parser.add_argument("--parley-root", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--arabic-font", required=True, type=Path)
    parser.add_argument("--japanese-font", required=True, type=Path)
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
        help="fail when Cangjie is not faster in any matrix row",
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
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
            "fallback",
            args.roboto,
            Path("tests/data/parley-fallback.txt"),
            "Roboto",
            "200",
            args.fallback_font,
        ),
    )
    failures: list[str] = []
    for case in cases:
        matrix_rows = (("layout", "fallback"), ("reflow", "fallback")) if case.name == "fallback" else (
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
        )
        for phase, style in matrix_rows:
            cangjie_first = run(
                cangjie_command(args.cangjie, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            parley_first = run(
                parley_command(parley, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            parley_second = run(
                parley_command(parley, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            cangjie_second = run(
                cangjie_command(args.cangjie, case, style, phase, args.iterations, args.samples),
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
            # hash encodings intentionally differ (Cangjie uses Wyhash over its
            # public layout records; Parley uses FNV over line/glyph fields),
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
            if args.fail_on_slower and speedup <= 1.0:
                failures.append(
                    f"{case.name}/{phase}/{style}: Cangjie slower "
                    f"({speedup:.3f}x)"
                )
            print(
                f"{case.name}/{phase}/{style}: "
                f"cangjie_ns={cangjie_a:.3f}/{cangjie_b:.3f} "
                f"parley_ns={parley_a:.3f}/{parley_b:.3f} "
                f"speedup={speedup:.3f}x glyphs={cangjie_first.get('glyphs')} "
                f"lines={cangjie_first.get('lines')} "
                f"objects={cangjie_first.get('objects')} "
                f"geometry_equal={str(geometry_equivalent).lower()} "
                f"object_geometry_equal="
                f"{str(object_geometry_equivalent).lower() if requires_object_geometry else 'n/a'}"
            )
    if failures:
        print("Cangjie/Parley matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Cangjie/Parley output-count and object-geometry matrix passed: 32 cases")
    print(f"parley_vertical_api={str(parley_vertical_api).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
