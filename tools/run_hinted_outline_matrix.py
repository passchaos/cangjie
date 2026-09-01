#!/usr/bin/env python3
"""Run matched FreeType/Cangjie hinted-outline rows in A/B/B/A order."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence


@dataclass(frozen=True)
class Case:
    name: str
    font: Path
    codepoint: str
    system_213_v40_mono_compatible: bool = True


@dataclass(frozen=True)
class TimingBlock:
    """One symmetric pair of per-engine process medians."""

    cangjie_ns: float
    freetype_ns: float
    raw_cangjie_ns: tuple[float, float]
    raw_freetype_ns: tuple[float, float]
    checksum: str

    @property
    def speedup(self) -> float:
        return self.freetype_ns / self.cangjie_ns


BLOCK_ORDERS = (
    ("cangjie", "freetype", "freetype", "cangjie"),
    ("freetype", "cangjie", "cangjie", "freetype"),
)


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


def geometric_mean(values: Sequence[float]) -> float:
    """Return a stable geometric mean without multiplying large timings."""
    if not values or any(not math.isfinite(value) or value <= 0 for value in values):
        raise ValueError("geometric mean requires positive finite values")
    return math.exp(math.fsum(math.log(value) for value in values) / len(values))


def block_order(index: int) -> tuple[str, str, str, str]:
    """Alternate the initial A/B/B/A block with its B/A/A/B reverse."""
    if index < 0:
        raise ValueError("block index must be non-negative")
    return BLOCK_ORDERS[index % len(BLOCK_ORDERS)]


def timing_block(
    commands: dict[str, list[str]],
    cpu: int | None,
    order: tuple[str, str, str, str],
    expected_checksum: str | None = None,
    run_command: Callable[[list[str], int | None], dict[str, str]] = run,
) -> TimingBlock:
    """Run one symmetric block, rejecting any semantic mismatch immediately."""
    records: dict[str, list[dict[str, str]]] = {
        "cangjie": [],
        "freetype": [],
    }
    for engine in order:
        records[engine].append(run_command(commands[engine], cpu))

    checksums = {
        record.get("checksum")
        for engine_records in records.values()
        for record in engine_records
    }
    if len(checksums) != 1 or None in checksums:
        raise ValueError(f"checksum mismatch {checksums}")
    checksum = next(iter(checksums))
    if checksum != expected_checksum and expected_checksum is not None:
        raise ValueError(
            f"checksum mismatch across blocks "
            f"{expected_checksum}/{checksum}"
        )

    raw_cangjie = tuple(
        float(record["sample_median_ns_per_iter"])
        for record in records["cangjie"]
    )
    raw_freetype = tuple(
        float(record["sample_median_ns_per_iter"])
        for record in records["freetype"]
    )
    if len(raw_cangjie) != 2 or len(raw_freetype) != 2:
        raise ValueError("a timing block requires two runs from each engine")
    return TimingBlock(
        cangjie_ns=geometric_mean(raw_cangjie),
        freetype_ns=geometric_mean(raw_freetype),
        raw_cangjie_ns=raw_cangjie,
        raw_freetype_ns=raw_freetype,
        checksum=checksum,
    )


def aggregate_speedup(blocks: list[TimingBlock]) -> float:
    return geometric_mean([block.speedup for block in blocks])


def passes_gate(speedup: float) -> bool:
    """The strict gate requires Cangjie to be faster than FreeType."""
    return speedup > 1.0


def raw_medians(values: tuple[float, float]) -> str:
    return ",".join(f"{value:.3f}" for value in values)


def format_block(block: TimingBlock) -> str:
    return (
        f"cangjie={block.cangjie_ns:.3f}ns "
        f"freetype={block.freetype_ns:.3f}ns "
        f"speedup={block.speedup:.3f}x "
        f"raw_cangjie_ns={raw_medians(block.raw_cangjie_ns)} "
        f"raw_freetype_ns={raw_medians(block.raw_freetype_ns)}"
    )


def measure_row(
    label: str,
    commands: dict[str, list[str]],
    cpu: int | None,
    strict: bool,
    run_command: Callable[[list[str], int | None], dict[str, str]] = run,
    emit: Callable[[str], None] = print,
) -> str | None:
    """Measure a row and confirm only a first-block strict failure."""
    try:
        blocks = [
            timing_block(
                commands, cpu, block_order(0), run_command=run_command,
            ),
        ]
    except ValueError as error:
        # A semantic mismatch is never retried: repeating a bad result could
        # hide nondeterminism behind aggregation.
        return f"{label}: {error}"

    block = blocks[0]
    emit(
        f"{label}: {format_block(block)} block=1 order=ABBA confirmation="
        f"{'not-needed' if not strict or passes_gate(block.speedup) else 'pending'}",
    )
    if not strict or passes_gate(block.speedup):
        return None

    emit(f"{label}: confirmation=started first_speedup={block.speedup:.3f}x")
    try:
        for block_index in (1, 2):
            confirmation = timing_block(
                commands,
                cpu,
                block_order(block_index),
                blocks[0].checksum,
                run_command,
            )
            blocks.append(confirmation)
            order_label = "BAAB" if block_index == 1 else "ABBA"
            emit(
                f"{label}: block={block_index + 1} order={order_label} "
                f"{format_block(confirmation)}",
            )
    except ValueError as error:
        return f"{label}: {error}"

    speedup = aggregate_speedup(blocks)
    status = "pass" if passes_gate(speedup) else "fail"
    emit(
        f"{label}: confirmation={status} blocks=3 "
        f"aggregate_speedup={speedup:.3f}x",
    )
    if passes_gate(speedup):
        return None
    return (
        f"{label}: performance aggregate_speedup={speedup:.3f}x "
        f"blocks=3"
    )


def self_test() -> None:
    """Exercise retry aggregation without invoking benchmark binaries."""
    assert block_order(0) == ("cangjie", "freetype", "freetype", "cangjie")
    assert block_order(1) == ("freetype", "cangjie", "cangjie", "freetype")
    assert block_order(2) == block_order(0)
    assert math.isclose(geometric_mean([4.0, 9.0]), 6.0)

    # An exact aggregate boundary preserves the strict contract: parity is not
    # sufficient for a claim that Cangjie is faster.
    boundary = [
        TimingBlock(2.0, 1.0, (2.0, 2.0), (1.0, 1.0), "same"),
        TimingBlock(1.0, 1.0, (1.0, 1.0), (1.0, 1.0), "same"),
        TimingBlock(1.0, 2.0, (1.0, 1.0), (2.0, 2.0), "same"),
    ]
    boundary_speedup = aggregate_speedup(boundary)
    assert math.isclose(boundary_speedup, 1.0)
    assert not passes_gate(boundary_speedup)
    assert not passes_gate(math.nextafter(1.0, 0.0))

    # A passing row consumes one block, while an initial strict failure runs
    # the two alternating confirmations. Keep these lifecycle guarantees pure
    # so the test does not need installed fonts or a benchmark executable.
    def scripted_runner(
        values: tuple[tuple[float, float, float, float], ...],
        checksums: tuple[str, ...] | None = None,
    ) -> tuple[Callable[[list[str], int | None], dict[str, str]], list[str]]:
        medians = iter(value for block_values in values for value in block_values)
        checksum_values = iter(
            checksums if checksums is not None else ("same",) * (len(values) * 4)
        )
        calls: list[str] = []

        def fake(command: list[str], cpu: int | None) -> dict[str, str]:
            del cpu
            calls.append(command[-1])
            return {
                "checksum": next(checksum_values),
                "sample_median_ns_per_iter": str(next(medians)),
            }

        return fake, calls

    passing_run, passing_calls = scripted_runner(((1.0, 2.0, 2.0, 1.0),))
    passing_output: list[str] = []
    assert measure_row(
        "passing",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        passing_run,
        passing_output.append,
    ) is None
    assert passing_calls == ["cangjie", "freetype", "freetype", "cangjie"]
    assert "raw_cangjie_ns=1.000,1.000" in passing_output[0]
    assert "confirmation=not-needed" in passing_output[0]

    report_only_run, report_only_calls = scripted_runner(
        ((2.0, 1.0, 1.0, 2.0),),
    )
    assert measure_row(
        "report-only",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        False,
        report_only_run,
        lambda line: None,
    ) is None
    assert len(report_only_calls) == 4

    reversed_run, reversed_calls = scripted_runner(((4.0, 8.0, 18.0, 16.0),))
    block = timing_block(
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        block_order(1),
        run_command=reversed_run,
    )
    assert reversed_calls == ["freetype", "cangjie", "cangjie", "freetype"]
    assert block.raw_cangjie_ns == (8.0, 18.0)
    assert block.raw_freetype_ns == (4.0, 16.0)
    assert math.isclose(block.cangjie_ns, 12.0)
    assert math.isclose(block.freetype_ns, 8.0)
    assert math.isclose(block.speedup, 2.0 / 3.0)
    assert block.checksum == "same"

    recovered_run, recovered_calls = scripted_runner((
        (2.0, 1.0, 1.0, 2.0),
        (2.0, 1.0, 1.0, 2.0),
        (1.0, 2.0, 2.0, 1.0),
    ))
    recovered_output: list[str] = []
    assert measure_row(
        "recovered",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        recovered_run,
        recovered_output.append,
    ) is None
    assert recovered_calls == [
        "cangjie", "freetype", "freetype", "cangjie",
        "freetype", "cangjie", "cangjie", "freetype",
        "cangjie", "freetype", "freetype", "cangjie",
    ]
    assert any("block=2 order=BAAB" in line for line in recovered_output)
    assert any("block=3 order=ABBA" in line for line in recovered_output)
    assert recovered_output[-1].endswith(
        "confirmation=pass blocks=3 aggregate_speedup=1.260x"
    )

    failed_run, failed_calls = scripted_runner((
        (2.0, 1.0, 1.0, 2.0),
        (1.0, 2.0, 2.0, 1.0),
        (2.0, 1.0, 1.0, 2.0),
    ))
    failure = measure_row(
        "failed",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        failed_run,
        lambda line: None,
    )
    assert failure is not None and "aggregate_speedup=0.500x" in failure
    assert len(failed_calls) == 12

    mismatch_run, mismatch_calls = scripted_runner(
        ((2.0, 1.0, 1.0, 2.0),),
        ("a", "b", "a", "a"),
    )
    mismatch = measure_row(
        "mismatch",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        mismatch_run,
        lambda line: None,
    )
    assert mismatch is not None and "checksum mismatch" in mismatch
    assert len(mismatch_calls) == 4

    cross_block_run, cross_block_calls = scripted_runner(
        (
            (2.0, 1.0, 1.0, 2.0),
            (1.0, 2.0, 2.0, 1.0),
        ),
        ("first",) * 4 + ("changed",) * 4,
    )
    cross_block = measure_row(
        "cross-block-mismatch",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        cross_block_run,
        lambda line: None,
    )
    assert cross_block is not None and "checksum mismatch across blocks" in cross_block
    # Stop before the third block rather than allowing later output to mask a
    # semantically unstable confirmation.
    assert len(cross_block_calls) == 8

    command_calls = 0

    def failed_command(
        command: list[str], cpu: int | None,
    ) -> dict[str, str]:
        nonlocal command_calls
        del command, cpu
        command_calls += 1
        raise RuntimeError("command failed")

    try:
        measure_row(
            "command-failure",
            {"cangjie": ["cangjie"], "freetype": ["freetype"]},
            None,
            True,
            failed_command,
            lambda line: None,
        )
    except RuntimeError:
        pass
    else:
        raise AssertionError("command failure was swallowed or retried")
    assert command_calls == 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glyph-bench", type=Path)
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
    parser.add_argument(
        "--self-test", action="store_true",
        help="run pure retry/aggregation tests without benchmark binaries",
    )
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("hinted outline matrix self-tests passed")
        return 0
    if args.glyph_bench is None:
        parser.error("--glyph-bench is required unless --self-test is used")
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    sizes = tuple(int(value) for value in args.sizes.split(","))
    if not sizes or any(value <= 0 for value in sizes):
        parser.error("sizes must be positive integers")

    cases = [
        Case("latin-a", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+0041"),
        Case("latin-x", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+0058"),
        Case("latin-compound", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+00C2"),
        Case("latin-compound-negative-round", Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), "U+00C3"),
        Case("devanagari", Path("/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf"), "U+0915"),
        Case("arabic", Path("/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf"), "U+0627"),
    ]
    if args.extended:
        cases.extend((
            Case("serif-cyrillic", Path("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"), "U+0416"),
            Case("freesans-latin", Path("/usr/share/fonts/truetype/freefont/FreeSans.ttf"), "U+0058"),
            Case("annapurna-devanagari", Path("/usr/share/fonts/truetype/annapurna/AnnapurnaSIL-Regular.ttf"), "U+0915"),
            Case(
                "liberation-compound",
                Path("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"),
                "U+00C2",
                False,
            ),
            Case("cascadia-latin", Path("/usr/share/fonts/truetype/cascadia-code/CascadiaCode.ttf"), "U+0058"),
            Case("noto-bengali", Path("/usr/share/fonts/truetype/noto/NotoSansBengali-Regular.ttf"), "U+0995"),
            Case("noto-tamil", Path("/usr/share/fonts/truetype/noto/NotoSansTamil-Regular.ttf"), "U+0B95"),
            Case(
                "noto-telugu",
                Path("/usr/share/fonts/truetype/noto/NotoSansTelugu-Regular.ttf"),
                "U+0C15",
                False,
            ),
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
    failures: list[str] = []
    rows = 0
    for case in cases:
        if not case.font.is_file():
            parser.error(f"missing fixture: {case.font}")
        for size in sizes:
            for interpreter in interpreters:
                for target in targets:
                    if (
                        not case.system_213_v40_mono_compatible
                        and interpreter == "cleartype"
                        and target == "mono"
                    ):
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
                    label = f"{case.name}/{size}/{interpreter}/{target}"
                    commands = {"cangjie": cj, "freetype": ft}
                    failure = measure_row(
                        label, commands, args.cpu, args.fail_on_slower,
                    )
                    if failure is not None:
                        failures.append(failure)
                    rows += 1
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    print(f"hinted outline matrix: {rows} semantic rows passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
