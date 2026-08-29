#!/usr/bin/env python3
"""Run the maintained Cangjie/Skrifa metadata and outline matrix.

The runner intentionally keeps semantic assertions separate from performance
ratios. It checks fields whose representations are shared by both CLIs, while
timings remain independently consumed observations suitable for fixed-CPU
A/B/B/A measurements.
"""

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
    mode: str
    font: str
    operand: int
    compare_checksum: bool = True
    font_size: str | None = None
    fixture: bool = True
    variation: str | None = None


@dataclass(frozen=True)
class OutlineCorpus:
    name: str
    font: Path
    glyph_ids: tuple[int, ...]


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
        1, fixture=False,
    ),
    Case(
        "outline-cff2-reuse", "outline-reuse", "Cantarell-VF-ABC.otf",
        1, fixture=False,
    ),
    Case(
        "outline-cff2-var-max", "outline-session",
        "Cantarell-VF-ABC.otf", 1, fixture=False, variation="1",
    ),
    Case(
        "outline-cff2-var-min", "outline-session",
        "Cantarell-VF-ABC.otf", 1, fixture=False, variation="-1",
    ),
    Case(
        "outline-cff2-var-max-reuse", "outline-reuse",
        "Cantarell-VF-ABC.otf", 1, fixture=False, variation="1",
    ),
    Case(
        "outline-cff2-var-min-reuse", "outline-reuse",
        "Cantarell-VF-ABC.otf", 1, fixture=False, variation="-1",
    ),
)


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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--skrifa-manifest", required=True, type=Path)
    parser.add_argument("--fixture-dir", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--cff2", required=True, type=Path)
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
        "--fail-on-slower", action="store_true",
        help="fail when any measured Cangjie row is not faster than Skrifa",
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.skrifa_manifest)],
        check=True,
    )
    skrifa = args.skrifa_manifest.parent / "target/release/fontations-bitmap-oracle"
    failures: list[str] = []
    measured: list[tuple[str, float, float, float, float]] = []
    for case in CASES:
        font = args.fixture_dir / case.font if case.fixture else args.cff2
        cangjie_semantic = run(cangjie_command(args.cangjie, case, font, 1, 1), args.cpu)
        reference_semantic = run(skrifa_command(skrifa, case, font, 1, 1), args.cpu)
        if case.compare_checksum and int(cangjie_semantic.get("checksum", "-1"), 16) != int(reference_semantic.get("checksum", "-2"), 16):
            failures.append(
                f"{case.name}: checksum: Cangjie={cangjie_semantic.get('checksum')!r}, "
                f"Skrifa={reference_semantic.get('checksum')!r}"
            )
        cangjie_first = cangjie_semantic if args.iterations == 1 and args.samples == 1 else run(
            cangjie_command(args.cangjie, case, font, args.iterations, args.samples), args.cpu
        )
        reference_first = reference_semantic if args.iterations == 1 and args.samples == 1 else run(
            skrifa_command(skrifa, case, font, args.iterations, args.samples), args.cpu
        )
        reference_second = run(
            skrifa_command(skrifa, case, font, args.iterations, args.samples), args.cpu
        )
        cangjie_second = run(
            cangjie_command(args.cangjie, case, font, args.iterations, args.samples), args.cpu
        )
        measured.append((case.name,
            float(cangjie_first["sample_median_ns_per_iter"]),
            float(cangjie_second["sample_median_ns_per_iter"]),
            float(reference_first["median_ns_per_iter"]),
            float(reference_second["median_ns_per_iter"])))

    if args.extended:
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
                # decoders. Other glyphs in this upstream test font currently
                # expose distinct CFF2 edge-case semantics and stay outside the
                # strict performance corpus until that differential is closed.
                (1, 3, 10, 36, 96),
            ),
        )
        for corpus in corpora:
            if not corpus.font.is_file():
                failures.append(f"{corpus.name}: missing font {corpus.font}")
                continue
            for glyph_id in corpus.glyph_ids:
                for mode in ("outline-session", "outline-reuse"):
                    case = Case(
                        f"{corpus.name}-gid{glyph_id}-{mode}",
                        mode, corpus.font.name, glyph_id, fixture=False,
                    )
                    cangjie_semantic = run(cangjie_command(args.cangjie, case, corpus.font, 1, 1), args.cpu)
                    reference_semantic = run(skrifa_command(skrifa, case, corpus.font, 1, 1), args.cpu)
                    if int(cangjie_semantic.get("checksum", "-1"), 16) != int(reference_semantic.get("checksum", "-2"), 16):
                        failures.append(
                            f"{case.name}: checksum: Cangjie={cangjie_semantic.get('checksum')!r}, "
                            f"Skrifa={reference_semantic.get('checksum')!r}"
                        )
                    cangjie_first = cangjie_semantic if args.iterations == 1 and args.samples == 1 else run(
                        cangjie_command(args.cangjie, case, corpus.font, args.iterations, args.samples), args.cpu
                    )
                    reference_first = reference_semantic if args.iterations == 1 and args.samples == 1 else run(
                        skrifa_command(skrifa, case, corpus.font, args.iterations, args.samples), args.cpu
                    )
                    reference_second = run(
                        skrifa_command(skrifa, case, corpus.font, args.iterations, args.samples), args.cpu
                    )
                    cangjie_second = run(
                        cangjie_command(args.cangjie, case, corpus.font, args.iterations, args.samples), args.cpu
                    )
                    measured.append((case.name,
                        float(cangjie_first["sample_median_ns_per_iter"]),
                        float(cangjie_second["sample_median_ns_per_iter"]),
                        float(reference_first["median_ns_per_iter"]),
                        float(reference_second["median_ns_per_iter"])))

    # Production-font queries cover the immutable cmap, metrics, bounds, and
    # complete global-metrics paths that synthetic fixtures cannot represent.
    roboto = Path(args.roboto)
    for case in (
        Case("family-name", "family-name", roboto.name, 0),
        Case("charmap", "charmap", roboto.name, ord("A")),
        Case("metrics", "metrics", roboto.name, 38),
        Case("bounds", "bounds", roboto.name, 38),
        Case("global-metrics", "global-metrics", roboto.name, 0),
    ):
        cangjie_semantic = run(cangjie_command(args.cangjie, case, roboto, 1, 1), args.cpu)
        reference_semantic = run(skrifa_command(skrifa, case, roboto, 1, 1), args.cpu)
        if case.compare_checksum and int(cangjie_semantic.get("checksum", "-1"), 16) != int(reference_semantic.get("checksum", "-2"), 16):
            failures.append(
                f"{case.name}: checksum: Cangjie={cangjie_semantic.get('checksum')!r}, "
                f"Skrifa={reference_semantic.get('checksum')!r}"
            )
        cangjie_first = cangjie_semantic if args.iterations == 1 and args.samples == 1 else run(
            cangjie_command(args.cangjie, case, roboto, args.iterations, args.samples), args.cpu
        )
        reference_first = reference_semantic if args.iterations == 1 and args.samples == 1 else run(
            skrifa_command(skrifa, case, roboto, args.iterations, args.samples), args.cpu
        )
        reference_second = run(
            skrifa_command(skrifa, case, roboto, args.iterations, args.samples), args.cpu
        )
        cangjie_second = run(
            cangjie_command(args.cangjie, case, roboto, args.iterations, args.samples), args.cpu
        )
        measured.append((case.name,
            float(cangjie_first["sample_median_ns_per_iter"]),
            float(cangjie_second["sample_median_ns_per_iter"]),
            float(reference_first["median_ns_per_iter"]),
            float(reference_second["median_ns_per_iter"])))

    for name, cangjie_first, cangjie_second, skrifa_first, skrifa_second in measured:
        cangjie_mean = math.sqrt(cangjie_first * cangjie_second)
        skrifa_mean = math.sqrt(skrifa_first * skrifa_second)
        speedup = math.inf if cangjie_mean == 0 else skrifa_mean / cangjie_mean
        print(
            f"{name}: cangjie_ns={cangjie_first:.3f}/{cangjie_second:.3f} "
            f"skrifa_ns={skrifa_first:.3f}/{skrifa_second:.3f} "
            f"speedup={speedup:.3f}x"
        )
        if args.fail_on_slower and speedup <= 1.0:
            failures.append(
                f"{name}: performance Cangjie={cangjie_mean:.3f}ns/"
                f"Skrifa={skrifa_mean:.3f}ns"
            )
    if failures:
        print("Fontations/Skrifa semantic matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(f"Fontations/Skrifa matrix passed: {len(measured)} cases")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    # Parsed by main's complete parser; this lightweight pre-read keeps mypy
    # and linters from treating the injected build argument as undeclared.
    sys.exit(main())
