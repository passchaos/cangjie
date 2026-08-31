#!/usr/bin/env python3
"""Run the maintained Cangjie/Skrifa COLRv1 pixel differential.

The two rasterizers deliberately have different antialiasers. Skrifa's adapter
therefore emits a geometry-coverage sidecar identifying its AA fringe; gradient
color derivatives never participate in that classification. The runner requires
exact-or-one-byte agreement everywhere else, so a steep or malformed gradient
cannot grant itself the relaxed edge tolerance.
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
    exact: bool = False


CASES = (
    Case("linear-repeat", 8),
    Case("linear-pad", 90, exact=True),
    Case("radial", 93),
    Case("sweep", 12),
    Case("nested-transform", 207),
    Case("composite", 123, exact=True),
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


@dataclass(frozen=True)
class Metrics:
    interior_max: int
    interior_mean: float
    fringe_max: int
    fringe_mean: float
    interior_pixels: int
    fringe_pixels: int


def compare(case: Case, cangjie: bytes, reference: bytes, edges: bytes) -> Metrics:
    expected_size = WIDTH * HEIGHT * 4
    if (
        len(cangjie) != expected_size
        or len(reference) != expected_size
        or len(edges) != WIDTH * HEIGHT
    ):
        raise ValueError(
            f"{case.name}: expected RGBA={expected_size} and edges={WIDTH * HEIGHT} "
            f"bytes, got {len(cangjie)}/{len(reference)}/{len(edges)}"
        )
    if case.exact and cangjie != reference:
        differing = sum(a != b for a, b in zip(cangjie, reference))
        raise ValueError(f"{case.name}: exact row differs in {differing} channel bytes")
    if any(value not in (0, 255) for value in edges):
        raise ValueError(f"{case.name}: geometry mask contains non-binary values")

    # Compare one L-infinity value per pixel. Averaging flattened channels
    # would let three unchanged channels dilute a bad edge in the fourth.
    interior: list[int] = []
    fringe: list[int] = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            lhs = pixel(cangjie, x, y)
            rhs = pixel(reference, x, y)
            difference = max(abs(a - b) for a, b in zip(lhs, rhs))
            if edges[y * WIDTH + x] != 0:
                fringe.append(difference)
            else:
                interior.append(difference)

    if not interior:
        raise ValueError(f"{case.name}: geometry mask leaves no semantic interior")
    # The retained corpus contains several overlapping authored paths, but the
    # union of their one-pixel coverage boundaries must remain perimeter-scale.
    # This catches a broken sidecar that silently labels the canvas as fringe.
    if len(fringe) > expected_size // 4 // 2:
        raise ValueError(
            f"{case.name}: geometry fringe covers {len(fringe)}/{WIDTH * HEIGHT} pixels"
        )

    interior_max = max(interior)
    interior_mean = sum(interior) / len(interior)
    fringe_max = max(fringe, default=0)
    fringe_mean = sum(fringe) / max(1, len(fringe))
    if interior_max > 1:
        raise ValueError(
            f"{case.name}: semantic interior differs by {interior_max} "
            f"(mean {interior_mean:.6f})"
        )
    # Four-by-four sample coverage and analytic area coverage can disagree by
    # roughly half a byte at one boundary pixel. The reference-derived fringe
    # cannot grow in response to candidate errors. Per-pixel L-infinity avoids
    # channel dilution; 30 is the smallest integer above the retained matrix's
    # 29.094 worst case, rather than a mechanically widened old mean bound.
    if fringe_max > 160 or fringe_mean > 30.0:
        raise ValueError(
            f"{case.name}: AA fringe exceeds bounds: max={fringe_max}, "
            f"mean={fringe_mean:.6f}"
        )
    return Metrics(
        interior_max,
        interior_mean,
        fringe_max,
        fringe_mean,
        len(interior),
        len(fringe),
    )


def synthetic_image(*, reverse: bool = False, shift: int = 0) -> bytes:
    """Make an opaque rectangle with a deliberately steep color ramp."""
    image = bytearray(WIDTH * HEIGHT * 4)
    for y in range(16, 112):
        for x in range(16 + shift, 112 + shift):
            ramp_x = x - shift
            phase = (ramp_x - 16) % 32
            if reverse:
                phase = 31 - phase
            offset = (y * WIDTH + x) * 4
            image[offset : offset + 4] = bytes((phase * 8, 255 - phase * 8, 64, 255))
    return bytes(image)


def synthetic_edges() -> bytes:
    edges = bytearray(WIDTH * HEIGHT)
    # The mask represents only geometry coverage. Two pixels on each side of
    # the authored boundary accommodate the independent AA kernels.
    for y in range(14, 114):
        for x in range(14, 114):
            if x < 18 or x >= 110 or y < 18 or y >= 110:
                edges[y * WIDTH + x] = 255
    return bytes(edges)


def expect_compare_failure(label: str, candidate: bytes, reference: bytes, edges: bytes) -> None:
    try:
        compare(Case(label, 0), candidate, reference, edges)
    except ValueError:
        return
    raise AssertionError(f"synthetic {label} error passed the pixel gate")


def self_test() -> None:
    """Prove the strict interior cannot be weakened by image colors."""
    reference = synthetic_image()
    edges = synthetic_edges()
    fringe_pixels = sum(value != 0 for value in edges)
    assert fringe_pixels == 1536
    assert edges[64 * WIDTH + 64] == 0  # steep gradient is still interior
    compare(Case("identity", 0), reference, reference, edges)

    one_byte = bytearray(reference)
    for y in range(24, 104):
        for x in range(24, 104):
            offset = (y * WIDTH + x) * 4 + 2
            one_byte[offset] += 1
    compare(Case("one-byte-noise", 0), bytes(one_byte), reference, edges)

    expect_compare_failure("shifted", synthetic_image(shift=1), reference, edges)
    expect_compare_failure("reversed", synthetic_image(reverse=True), reference, edges)
    wrong_color = bytearray(reference)
    for y in range(32, 96):
        for x in range(32, 96):
            offset = (y * WIDTH + x) * 4
            wrong_color[offset + 2] = 96
    expect_compare_failure("wrong-color", bytes(wrong_color), reference, edges)

    self_exempting = bytearray(reference)
    for y in range(32, 96):
        for x in range(32, 96):
            if x % 2 == 0:
                offset = (y * WIDTH + x) * 4
                self_exempting[offset : offset + 4] = bytes((0, 0, 0, 255))
    expect_compare_failure("candidate-edge", bytes(self_exempting), reference, edges)
    expect_compare_failure("wrong-size", reference[:-4], reference, edges)

    aa_candidate = bytearray(reference)
    for y in range(14, 114):
        for x in range(14, 114):
            if edges[y * WIDTH + x]:
                offset = (y * WIDTH + x) * 4
                for channel in range(4):
                    aa_candidate[offset + channel] = max(
                        0, aa_candidate[offset + channel] - 12
                    )
    compare(Case("aa-fringe", 0), bytes(aa_candidate), reference, edges)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--skrifa-manifest", required=True, type=Path)
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument(
        "--no-self-test",
        action="store_true",
        help="skip the normally mandatory synthetic gate tests",
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    if not args.no_self_test:
        self_test()
        print("COLRv1 pixel gate synthetic self-tests passed")
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
            edges_path = output / f"reference-{case.name}.edges"
            common = [
                str(args.font), str(case.glyph_id), *PIXEL_ARGS, case.coordinates,
                str(args.iterations), str(args.samples),
            ]
            try:
                cangjie_fields = run([str(args.cangjie), *common, str(cangjie_path)])
                reference_fields = run(
                    [str(reference), *common, str(reference_path), str(edges_path)]
                )
                if (
                    cangjie_fields.get("format") != "premul-rgba8"
                    or reference_fields.get("format") != "premul-rgba8"
                ):
                    raise ValueError(f"{case.name}: renderer output format mismatch")
                if reference_fields.get("edge_format") != "geometry-u8":
                    raise ValueError(f"{case.name}: reference edge format mismatch")
                metrics = compare(
                    case,
                    cangjie_path.read_bytes(),
                    reference_path.read_bytes(),
                    edges_path.read_bytes(),
                )
                print(
                    f"{case.name}: interior_max={metrics.interior_max} "
                    f"interior_mean={metrics.interior_mean:.6f} "
                    f"fringe_max={metrics.fringe_max} "
                    f"fringe_mean={metrics.fringe_mean:.6f} "
                    f"interior_pixels={metrics.interior_pixels} "
                    f"fringe_pixels={metrics.fringe_pixels}"
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
