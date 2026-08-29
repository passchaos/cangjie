#!/usr/bin/env python3
"""Run matched FreeType/Cangjie hinted-outline rows in A/B/B/A order."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
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
        print(completed.stdout, end="")
        raise RuntimeError(f"command failed: {' '.join(command)}")
    result: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", completed.stdout):
        if "=" in token:
            key, value = token.split("=", 1)
            result[key] = value
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glyph-bench", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=30000)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--sizes", default="9,16")
    parser.add_argument(
        "--extended", action="store_true",
        help="include additional installed-font/script fixtures",
    )
    parser.add_argument(
        "--fail-on-slower", action="store_true",
        help="fail when any Cangjie row is not faster than FreeType",
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    sizes = tuple(int(value) for value in args.sizes.split(","))
    if not sizes or any(value <= 0 for value in sizes):
        parser.error("sizes must be positive integers")

    cases = [
        Case("latin-a", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+0041"),
        Case("latin-x", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+0058"),
        Case("latin-compound", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+00C2"),
        Case("devanagari", Path("/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf"), "U+0915"),
        Case("arabic", Path("/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf"), "U+0627"),
    ]
    if args.extended:
        cases.extend((
            Case("serif-cyrillic", Path("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"), "U+0416"),
            Case("freesans-latin", Path("/usr/share/fonts/truetype/freefont/FreeSans.ttf"), "U+0058"),
            Case("annapurna-devanagari", Path("/usr/share/fonts/truetype/annapurna/AnnapurnaSIL-Regular.ttf"), "U+0915"),
            Case("liberation-compound", Path("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"), "U+00C2"),
            Case("cascadia-latin", Path("/usr/share/fonts/truetype/cascadia-code/CascadiaCode.ttf"), "U+0058"),
            Case("noto-bengali", Path("/usr/share/fonts/truetype/noto/NotoSansBengali-Regular.ttf"), "U+0995"),
            Case("noto-tamil", Path("/usr/share/fonts/truetype/noto/NotoSansTamil-Regular.ttf"), "U+0B95"),
            Case("noto-telugu", Path("/usr/share/fonts/truetype/noto/NotoSansTelugu-Regular.ttf"), "U+0C15"),
            Case("noto-kannada", Path("/usr/share/fonts/truetype/noto/NotoSansKannada-Regular.ttf"), "U+0C95"),
            Case("noto-malayalam", Path("/usr/share/fonts/truetype/noto/NotoSansMalayalam-Regular.ttf"), "U+0D15"),
            Case("noto-gujarati", Path("/usr/share/fonts/truetype/noto/NotoSansGujarati-Regular.ttf"), "U+0A95"),
            Case("noto-gurmukhi", Path("/usr/share/fonts/truetype/noto/NotoSansGurmukhi-Regular.ttf"), "U+0A15"),
            Case("noto-hebrew", Path("/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf"), "U+05D0"),
            Case("noto-thai", Path("/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf"), "U+0E01"),
            Case("noto-khmer", Path("/usr/share/fonts/truetype/noto/NotoSansKhmer-Regular.ttf"), "U+1780"),
        ))
    targets = ("normal", "light", "lcd", "vertical-lcd", "mono")
    interpreters = ("classic", "cleartype")
    # The system oracle is FreeType 2.13.2. FreeType 2.14 deliberately changed
    # v40 monochrome compound placement; these rows are gated separately by
    # `hinting-freetype-test` when a current FreeType is available.
    system_version_exclusions = {
        ("liberation-compound", "cleartype", "mono"),
        ("noto-telugu", "cleartype", "mono"),
    }
    failures: list[str] = []
    rows = 0
    for case in cases:
        if not case.font.is_file():
            parser.error(f"missing fixture: {case.font}")
        for size in sizes:
            for interpreter in interpreters:
                for target in targets:
                    if (case.name, interpreter, target) in system_version_exclusions:
                        continue
                    base = [
                        str(args.glyph_bench), "--mode", "hinted-outline",
                        "--font", str(case.font), "--codepoint", case.codepoint,
                        "--font-size", str(size), "--hinting-target", target,
                        "--hinting-interpreter", interpreter, "--iterations",
                        str(args.iterations), "--warmup",
                        str(max(1, args.iterations // 10)), "--samples",
                        str(args.samples),
                    ]
                    cj = [*base, "--engine", "cangjie"]
                    ft = [*base, "--engine", "freetype"]
                    cj_a = run(cj, args.cpu)
                    ft_a = run(ft, args.cpu)
                    ft_b = run(ft, args.cpu)
                    cj_b = run(cj, args.cpu)
                    checksums = {
                        cj_a.get("checksum"), ft_a.get("checksum"),
                        ft_b.get("checksum"), cj_b.get("checksum"),
                    }
                    label = f"{case.name}/{size}/{interpreter}/{target}"
                    if len(checksums) != 1:
                        failures.append(f"{label}: checksum mismatch {checksums}")
                    cj_ns = math.sqrt(
                        float(cj_a["sample_median_ns_per_iter"]) *
                        float(cj_b["sample_median_ns_per_iter"]),
                    )
                    ft_ns = math.sqrt(
                        float(ft_a["sample_median_ns_per_iter"]) *
                        float(ft_b["sample_median_ns_per_iter"]),
                    )
                    print(
                        f"{label}: cangjie={cj_ns:.3f}ns "
                        f"freetype={ft_ns:.3f}ns speedup={ft_ns / cj_ns:.3f}x",
                    )
                    if args.fail_on_slower and cj_ns >= ft_ns:
                        failures.append(
                            f"{label}: performance {cj_ns:.3f}ns/"
                            f"{ft_ns:.3f}ns",
                        )
                    rows += 1
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    print(f"hinted outline matrix: {rows} semantic rows passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
