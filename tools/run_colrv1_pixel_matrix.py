#!/usr/bin/env python3
"""Run the maintained Cangjie/Skrifa COLRv1 pixel differential.

The two rasterizers deliberately have different antialiasers. The comparison
therefore treats pixels next to an edge in either image as the AA fringe and
requires exact-or-one-byte agreement everywhere else. This is stricter than a
global image metric: a direction, transform, layer, clip, or variation error
necessarily changes a locally smooth region and fails the semantic gate.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

WIDTH = 128
HEIGHT = 128
FIXTURE_SHA256 = "5647de2386d42946624145a43e80982978727dd27701bb38b791474b8417b91f"
PIXEL_ARGS = ("96", str(WIDTH), str(HEIGHT), "16", "112", "0")
VARIABLE_ALPHA_LOCATION = ",".join(["0"] * 41 + ["-0.7"])


@dataclass(frozen=True)
class Case:
    name: str
    glyph_id: int
    coordinates: str = "-"


CASES = (
    Case("linear-repeat", 8),
    Case("linear-pad", 90),
    Case("radial", 93),
    Case("sweep", 12),
    Case("nested-transform", 207),
    Case("composite", 123),
    Case("clip-composite", 156),
    Case("colrglyph", 180),
    Case("variable-alpha-default", 177),
    Case("variable-alpha", 177, VARIABLE_ALPHA_LOCATION),
)


def run(command: list[str]) -> dict[str, str]:
    completed = subprocess.run(
        command, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr, end="")
        print(completed.stderr, file=sys.stderr, end="")
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}")
    fields: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", completed.stdout + completed.stderr):
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def pixel(data: bytes, x: int, y: int) -> tuple[int, int, int, int]:
    offset = (y * WIDTH + x) * 4
    return tuple(data[offset : offset + 4])  # type: ignore[return-value]


def is_edge(data: bytes, x: int, y: int) -> bool:
    """Identify a one-pixel neighborhood of coverage or color boundaries.

    A four-unit step is larger than both engines' <=1-unit smooth-region
    numerical noise. Marking color as well as alpha transitions is important:
    overlapping transformed layers can have fully opaque, antialiased internal
    boundaries. Marking edges independently avoids choosing either renderer as
    the geometry authority.
    """
    center = pixel(data, x, y)
    for neighbor_y in range(max(0, y - 1), min(HEIGHT, y + 2)):
        for neighbor_x in range(max(0, x - 1), min(WIDTH, x + 2)):
            neighbor = pixel(data, neighbor_x, neighbor_y)
            if max(abs(a - b) for a, b in zip(center, neighbor)) > 4:
                return True
    return False


def compare(case: Case, cangjie: bytes, reference: bytes) -> tuple[int, float, int, float]:
    expected_size = WIDTH * HEIGHT * 4
    if len(cangjie) != expected_size or len(reference) != expected_size:
        raise ValueError(
            f"{case.name}: expected {expected_size} bytes, got "
            f"{len(cangjie)}/{len(reference)}"
        )
    interior: list[int] = []
    fringe: list[int] = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            lhs = pixel(cangjie, x, y)
            rhs = pixel(reference, x, y)
            differences = [abs(a - b) for a, b in zip(lhs, rhs)]
            if is_edge(cangjie, x, y) or is_edge(reference, x, y):
                fringe.extend(differences)
            else:
                interior.extend(differences)

    interior_max = max(interior, default=0)
    interior_mean = sum(interior) / max(1, len(interior))
    fringe_max = max(fringe, default=0)
    fringe_mean = sum(fringe) / max(1, len(fringe))
    if interior_max > 1:
        raise ValueError(
            f"{case.name}: semantic interior differs by {interior_max} "
            f"(mean {interior_mean:.6f})"
        )
    # Four-by-four sample coverage and analytic area coverage can disagree by
    # roughly half a byte at a single boundary pixel. Bounding the whole edge
    # neighborhood prevents a shifted/missing edge from being hidden.
    if fringe_max > 160 or fringe_mean > 8.0:
        raise ValueError(
            f"{case.name}: AA fringe exceeds bounds: max={fringe_max}, "
            f"mean={fringe_mean:.6f}"
        )
    return interior_max, interior_mean, fringe_max, fringe_mean


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--skrifa-manifest", required=True, type=Path)
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    for label, path in (("cangjie", args.cangjie), ("font", args.font)):
        if not path.is_file():
            parser.error(f"{label} path does not exist: {path}")
    actual_fixture_hash = hashlib.sha256(args.font.read_bytes()).hexdigest()
    if actual_fixture_hash != FIXTURE_SHA256:
        parser.error(
            "font is not the pinned COLRv1 corpus: "
            f"{actual_fixture_hash} != {FIXTURE_SHA256}"
        )

    build = subprocess.run(
        [
            "cargo", "build", "--release", "--locked", "--offline",
            "--manifest-path", str(args.skrifa_manifest),
        ],
        check=False,
    )
    if build.returncode != 0:
        return build.returncode
    reference = args.skrifa_manifest.parent / "target/release/colrv1-pixel-oracle"

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="cangjie-colrv1-pixels-") as directory:
        output = Path(directory)
        for case in CASES:
            cangjie_path = output / f"cangjie-{case.name}.rgba"
            reference_path = output / f"reference-{case.name}.rgba"
            common = [
                str(args.font), str(case.glyph_id), *PIXEL_ARGS, case.coordinates,
                str(args.iterations), str(args.samples),
            ]
            try:
                cangjie_fields = run([str(args.cangjie), *common, str(cangjie_path)])
                reference_fields = run([str(reference), *common, str(reference_path)])
                if cangjie_fields.get("format") != "premul-rgba8" or reference_fields.get("format") != "premul-rgba8":
                    raise ValueError(f"{case.name}: renderer output format mismatch")
                metrics = compare(case, cangjie_path.read_bytes(), reference_path.read_bytes())
                print(
                    f"{case.name}: interior_max={metrics[0]} "
                    f"interior_mean={metrics[1]:.6f} "
                    f"fringe_max={metrics[2]} fringe_mean={metrics[3]:.6f}"
                )
            except (OSError, RuntimeError, ValueError) as error:
                failures.append(str(error))

    if failures:
        print("Cangjie/Skrifa COLRv1 pixel matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(f"Cangjie/Skrifa COLRv1 pixel matrix completed: {len(CASES)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
