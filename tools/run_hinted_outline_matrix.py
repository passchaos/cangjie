#!/usr/bin/env python3
"""Run matched FreeType/Cangjie hinted-outline rows in A/B/B/A order."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence


TOOL_NAME = "run_hinted_outline_matrix.py"
TOOL_VERSION = "1.0"
REPORT_SCHEMA_VERSION = 1


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


@dataclass(frozen=True)
class BlockResult:
    """One completed A/B/B/A or B/A/A/B confirmation block."""

    index: int
    order_label: str
    order: tuple[str, str, str, str]
    timing: TimingBlock


@dataclass(frozen=True)
class RowSpec:
    """Identity fields that describe one potential matrix row."""

    label: str
    case_name: str
    font: Path
    codepoint: str
    size: int
    interpreter: str
    target: str
    system_213_v40_mono_compatible: bool


@dataclass(frozen=True)
class RowResult:
    """A completed row with enough evidence to audit its final status."""

    row: RowSpec
    blocks: tuple[BlockResult, ...]
    aggregate_speedup: float
    final_gate_status: str
    confirmation_status: str


@dataclass(frozen=True)
class SkippedRow:
    """A manifest row intentionally excluded from execution."""

    row: RowSpec
    reason: str


@dataclass(frozen=True)
class RunConfiguration:
    """Inputs that affect how a hinted-outline matrix should be interpreted."""

    glyph_bench: Path
    iterations: int
    samples: int
    warmup_iterations: int
    cpu: int | None
    sizes: tuple[int, ...]
    extended: bool
    fail_on_slower: bool
    minimum_speedup: float


@dataclass(frozen=True)
class MatrixOutcome:
    """Completed runner state used by CLI output and optional JSON emission."""

    manifest: tuple[RowSpec, ...]
    results: tuple[RowResult, ...]
    skipped_rows: tuple[SkippedRow, ...]
    failures: tuple[str, ...]


BLOCK_ORDERS = (
    ("cangjie", "freetype", "freetype", "cangjie"),
    ("freetype", "cangjie", "cangjie", "freetype"),
)
DEFAULT_MINIMUM_SPEEDUP = 1.01


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
    checksum = expected_checksum
    for engine in order:
        record = run_command(commands[engine], cpu)
        record_checksum = record.get("checksum")
        if record_checksum is None:
            raise ValueError("checksum missing from benchmark output")
        if checksum is None:
            checksum = record_checksum
        elif record_checksum != checksum:
            scope = " across blocks" if expected_checksum is not None else ""
            raise ValueError(
                f"checksum mismatch{scope} {checksum}/{record_checksum}"
            )
        records[engine].append(record)
    assert checksum is not None

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


def valid_minimum_speedup(minimum_speedup: float) -> bool:
    """A strict performance margin must be finite and exceed parity."""
    return math.isfinite(minimum_speedup) and minimum_speedup > 1.0


def passes_gate(
    speedup: float, minimum_speedup: float = DEFAULT_MINIMUM_SPEEDUP
) -> bool:
    """Treat the declared boundary itself as a passing measurement."""
    return not math.isnan(speedup) and speedup >= minimum_speedup


def raw_medians(values: tuple[float, float]) -> str:
    return ",".join(f"{value:.3f}" for value in values)


def order_label(index: int) -> str:
    """Render the alternating block order using the historic short labels."""
    return "ABBA" if block_order(index) == BLOCK_ORDERS[0] else "BAAB"


def format_block(block: TimingBlock) -> str:
    return (
        f"cangjie={block.cangjie_ns:.3f}ns "
        f"freetype={block.freetype_ns:.3f}ns "
        f"speedup={block.speedup:.3f}x "
        f"raw_cangjie_ns={raw_medians(block.raw_cangjie_ns)} "
        f"raw_freetype_ns={raw_medians(block.raw_freetype_ns)}"
    )


def measure_row(
    row: RowSpec,
    label: str,
    commands: dict[str, list[str]],
    cpu: int | None,
    strict: bool,
    run_command: Callable[[list[str], int | None], dict[str, str]] = run,
    emit: Callable[[str], None] = print,
    minimum_speedup: float = DEFAULT_MINIMUM_SPEEDUP,
) -> tuple[str | None, RowResult | None]:
    """Measure a row and confirm only a first-block strict failure."""
    try:
        first_timing = timing_block(
            commands, cpu, block_order(0), run_command=run_command,
        )
    except ValueError as error:
        # A semantic mismatch is never retried: repeating a bad result could
        # hide nondeterminism behind aggregation.
        return f"{label}: {error}", None

    blocks = [
        BlockResult(
            index=1,
            order_label=order_label(0),
            order=block_order(0),
            timing=first_timing,
        ),
    ]
    block = blocks[0].timing
    # Keep report-only output compatible with the original one-line format.
    # Strict runs add the raw process medians needed to diagnose noisy rows.
    if not strict:
        emit(
            f"{label}: cangjie={block.cangjie_ns:.3f}ns "
            f"freetype={block.freetype_ns:.3f}ns "
            f"speedup={block.speedup:.3f}x "
            f"minimum_speedup={minimum_speedup:.3f}x",
        )
        return (
            None,
            RowResult(
                row=row,
                blocks=tuple(blocks),
                aggregate_speedup=block.speedup,
                final_gate_status=(
                    "met"
                    if passes_gate(block.speedup, minimum_speedup)
                    else "below-minimum"
                ),
                confirmation_status="not-needed",
            ),
        )
    emit(
        f"{label}: {format_block(block)} block=1 order=ABBA "
        f"minimum_speedup={minimum_speedup:.3f}x confirmation="
        f"{'not-needed' if passes_gate(block.speedup, minimum_speedup) else 'pending'}",
    )
    if passes_gate(block.speedup, minimum_speedup):
        return (
            None,
            RowResult(
                row=row,
                blocks=tuple(blocks),
                aggregate_speedup=block.speedup,
                final_gate_status="met",
                confirmation_status="not-needed",
            ),
        )

    emit(
        f"{label}: confirmation=started first_speedup={block.speedup:.3f}x "
        f"minimum_speedup={minimum_speedup:.3f}x"
    )
    try:
        for block_index in (1, 2):
            confirmation = timing_block(
                commands,
                cpu,
                block_order(block_index),
                blocks[0].timing.checksum,
                run_command,
            )
            block_result = BlockResult(
                index=block_index + 1,
                order_label=order_label(block_index),
                order=block_order(block_index),
                timing=confirmation,
            )
            blocks.append(block_result)
            emit(
                f"{label}: block={block_index + 1} order={block_result.order_label} "
                f"{format_block(confirmation)}",
            )
    except ValueError as error:
        return f"{label}: {error}", None

    speedup = aggregate_speedup([completed.timing for completed in blocks])
    status = "pass" if passes_gate(speedup, minimum_speedup) else "fail"
    emit(
        f"{label}: confirmation={status} blocks=3 "
        f"aggregate_speedup={speedup:.3f}x "
        f"minimum_speedup={minimum_speedup:.3f}x",
    )
    if passes_gate(speedup, minimum_speedup):
        return (
            None,
            RowResult(
                row=row,
                blocks=tuple(blocks),
                aggregate_speedup=speedup,
                final_gate_status="met",
                confirmation_status="pass",
            ),
        )
    return (
        f"{label}: performance aggregate_speedup={speedup:.3f}x "
        f"blocks=3 minimum_speedup={minimum_speedup:.3f}x",
        RowResult(
            row=row,
            blocks=tuple(blocks),
            aggregate_speedup=speedup,
            final_gate_status="below-minimum",
            confirmation_status="fail",
        ),
    )


def row_spec_json(row: RowSpec) -> dict[str, Any]:
    """Return the stable identity fields for one manifest or skipped row."""
    return {
        "label": row.label,
        "case": row.case_name,
        "font": str(row.font),
        "codepoint": row.codepoint,
        "size": row.size,
        "interpreter": row.interpreter,
        "target": row.target,
        "system_213_v40_mono_compatible": (
            row.system_213_v40_mono_compatible
        ),
    }


def block_result_json(block: BlockResult) -> dict[str, Any]:
    """Render one measured block with enough detail to audit noise and order."""
    return {
        "index": block.index,
        "order_label": block.order_label,
        "order": list(block.order),
        "checksum": block.timing.checksum,
        "engines": {
            "cangjie": {
                "geometric_mean_ns_per_iter": block.timing.cangjie_ns,
                "raw_medians_ns_per_iter": list(block.timing.raw_cangjie_ns),
            },
            "freetype": {
                "geometric_mean_ns_per_iter": block.timing.freetype_ns,
                "raw_medians_ns_per_iter": list(block.timing.raw_freetype_ns),
            },
        },
        "speedup": block.timing.speedup,
    }


def row_result_json(result: RowResult) -> dict[str, Any]:
    """Return the machine-readable representation of one completed row."""
    return {
        **row_spec_json(result.row),
        "blocks": [block_result_json(block) for block in result.blocks],
        "aggregate_speedup": result.aggregate_speedup,
        "final_gate_status": result.final_gate_status,
        "confirmation_status": result.confirmation_status,
    }


def build_json_report(
    configuration: RunConfiguration,
    outcome: MatrixOutcome,
) -> dict[str, Any]:
    """Build an auditable artifact only from a complete non-failing matrix."""
    if outcome.failures:
        raise ValueError("cannot build a completed report from a failing matrix")
    expected_labels = [row.label for row in outcome.manifest]
    result_labels = [result.row.label for result in outcome.results]
    if result_labels != expected_labels:
        raise ValueError(
            "cannot build report from a partial, reordered, or mismatched "
            f"matrix: expected {expected_labels}, got {result_labels}"
        )
    below_minimum = [
        result.row.label
        for result in outcome.results
        if result.final_gate_status != "met"
    ]
    gate_mode = "enforced" if configuration.fail_on_slower else "report-only"
    thresholds_met = not below_minimum
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "tool": {"name": TOOL_NAME, "version": TOOL_VERSION},
        "run": {
            "glyph_bench": str(configuration.glyph_bench),
            "iterations": configuration.iterations,
            "samples": configuration.samples,
            "warmup_iterations": configuration.warmup_iterations,
            "cpu": configuration.cpu,
            "sizes": list(configuration.sizes),
            "extended": configuration.extended,
            "fail_on_slower": configuration.fail_on_slower,
            "minimum_speedup": configuration.minimum_speedup,
            "block_orders": [list(order) for order in BLOCK_ORDERS],
        },
        "gate": {
            "mode": gate_mode,
            "minimum_speedup": configuration.minimum_speedup,
            "thresholds_met": thresholds_met,
            "command_succeeded": thresholds_met or not configuration.fail_on_slower,
        },
        "manifest": {
            "rows": [row_spec_json(row) for row in outcome.manifest],
            "skipped_rows": [
                {
                    **row_spec_json(skipped.row),
                    "reason": skipped.reason,
                }
                for skipped in outcome.skipped_rows
            ],
        },
        "rows": [row_result_json(result) for result in outcome.results],
        "summary": {
            "executed_row_count": len(outcome.results),
            "skipped_row_count": len(outcome.skipped_rows),
            "thresholds_met_count": len(outcome.results) - len(below_minimum),
            "below_minimum_count": len(below_minimum),
            "below_minimum_rows": below_minimum,
        },
    }


def write_json_atomic(path: Path, report: Mapping[str, Any]) -> None:
    """Durably replace ``path`` without exposing a partial JSON document."""
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
    outcome: MatrixOutcome,
) -> None:
    """Write evidence for a completed outcome, if the caller requested it."""
    if path is None:
        return
    write_json_atomic(path, build_json_report(configuration, outcome))


def row_spec(
    case: Case, size: int, interpreter: str, target: str
) -> RowSpec:
    """Build one row identity from the case and CLI dimensions."""
    return RowSpec(
        label=f"{case.name}/{size}/{interpreter}/{target}",
        case_name=case.name,
        font=case.font,
        codepoint=case.codepoint,
        size=size,
        interpreter=interpreter,
        target=target,
        system_213_v40_mono_compatible=case.system_213_v40_mono_compatible,
    )


def self_test() -> None:
    """Exercise retry aggregation without invoking benchmark binaries."""
    assert block_order(0) == ("cangjie", "freetype", "freetype", "cangjie")
    assert block_order(1) == ("freetype", "cangjie", "cangjie", "freetype")
    assert block_order(2) == block_order(0)
    assert math.isclose(geometric_mean([4.0, 9.0]), 6.0)

    # Preserve the declared margin rather than accepting a noise-scale win.
    boundary = [
        TimingBlock(2.0, 1.0, (2.0, 2.0), (1.0, 1.0), "same"),
        TimingBlock(1.0, 1.0, (1.0, 1.0), (1.0, 1.0), "same"),
        TimingBlock(1.0, 2.0, (1.0, 1.0), (2.0, 2.0), "same"),
    ]
    boundary_speedup = aggregate_speedup(boundary)
    assert math.isclose(boundary_speedup, 1.0)
    assert valid_minimum_speedup(DEFAULT_MINIMUM_SPEEDUP)
    assert not valid_minimum_speedup(1.0)
    assert not valid_minimum_speedup(math.inf)
    assert not valid_minimum_speedup(math.nan)
    assert not passes_gate(1.0)
    assert not passes_gate(math.nextafter(DEFAULT_MINIMUM_SPEEDUP, 0.0))
    assert passes_gate(DEFAULT_MINIMUM_SPEEDUP)

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
    passing_spec = RowSpec(
        "passing", "passing", Path("font.ttf"), "U+0041", 12,
        "classic", "normal", True,
    )
    passing_failure, passing_result = measure_row(
        passing_spec,
        "passing",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        passing_run,
        passing_output.append,
    )
    assert passing_failure is None
    assert passing_result is not None and passing_result.final_gate_status == "met"
    assert passing_calls == ["cangjie", "freetype", "freetype", "cangjie"]
    assert "raw_cangjie_ns=1.000,1.000" in passing_output[0]
    assert "confirmation=not-needed" in passing_output[0]

    report_only_run, report_only_calls = scripted_runner(
        ((2.0, 1.0, 1.0, 2.0),),
    )
    report_only_output: list[str] = []
    report_only_spec = RowSpec(
        "report-only", "report-only", Path("font.ttf"), "U+0041", 12,
        "classic", "normal", True,
    )
    report_only_failure, report_only_result = measure_row(
        report_only_spec,
        "report-only",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        False,
        report_only_run,
        report_only_output.append,
    )
    assert report_only_failure is None
    assert report_only_result is not None
    assert report_only_result.final_gate_status == "below-minimum"
    assert len(report_only_calls) == 4
    assert report_only_output == [
        "report-only: cangjie=2.000ns freetype=1.000ns speedup=0.500x "
        "minimum_speedup=1.010x",
    ]

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
    recovered_spec = RowSpec(
        "recovered", "recovered", Path("font.ttf"), "U+0041", 12,
        "classic", "normal", True,
    )
    recovered_failure, recovered_result = measure_row(
        recovered_spec,
        "recovered",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        recovered_run,
        recovered_output.append,
    )
    assert recovered_failure is None
    assert recovered_result is not None
    assert recovered_result.confirmation_status == "pass"
    assert recovered_calls == [
        "cangjie", "freetype", "freetype", "cangjie",
        "freetype", "cangjie", "cangjie", "freetype",
        "cangjie", "freetype", "freetype", "cangjie",
    ]
    assert any("block=2 order=BAAB" in line for line in recovered_output)
    assert any("block=3 order=ABBA" in line for line in recovered_output)
    assert recovered_output[-1].endswith(
        "confirmation=pass blocks=3 aggregate_speedup=1.260x "
        "minimum_speedup=1.010x"
    )

    failed_run, failed_calls = scripted_runner((
        (2.0, 1.0, 1.0, 2.0),
        (1.0, 2.0, 2.0, 1.0),
        (2.0, 1.0, 1.0, 2.0),
    ))
    failed_spec = RowSpec(
        "failed", "failed", Path("font.ttf"), "U+0041", 12,
        "classic", "normal", True,
    )
    failure, failed_result = measure_row(
        failed_spec,
        "failed",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        failed_run,
        lambda line: None,
    )
    assert failure is not None and "aggregate_speedup=0.500x" in failure
    assert failed_result is not None
    assert failed_result.final_gate_status == "below-minimum"
    assert len(failed_calls) == 12

    # A result that merely beats parity must still fail the shared 1% audit
    # margin. Keeping this in the runner's own self-test catches positional
    # call sites that accidentally omit the configured threshold.
    marginal_run, marginal_calls = scripted_runner((
        (1.0, 1.005, 1.005, 1.0),
        (1.005, 1.0, 1.0, 1.005),
        (1.0, 1.005, 1.005, 1.0),
    ))
    marginal_failure, marginal_result = measure_row(
        RowSpec(
            "marginal", "marginal", Path("font.ttf"), "U+0041", 12,
            "classic", "normal", True,
        ),
        "marginal",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        marginal_run,
        lambda line: None,
    )
    assert marginal_failure is not None
    assert "minimum_speedup=1.010x" in marginal_failure
    assert marginal_result is not None
    assert marginal_result.final_gate_status == "below-minimum"
    assert len(marginal_calls) == 12

    mismatch_run, mismatch_calls = scripted_runner(
        ((2.0, 1.0, 1.0, 2.0),),
        ("a", "b", "a", "a"),
    )
    mismatch, mismatch_result = measure_row(
        RowSpec("mismatch", "mismatch", Path("font.ttf"), "U+0041", 12,
                "classic", "normal", True),
        "mismatch",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        mismatch_run,
        lambda line: None,
    )
    assert mismatch is not None and "checksum mismatch" in mismatch
    assert mismatch_result is None
    assert len(mismatch_calls) == 2

    cross_block_run, cross_block_calls = scripted_runner(
        (
            (2.0, 1.0, 1.0, 2.0),
            (1.0, 2.0, 2.0, 1.0),
        ),
        ("first",) * 4 + ("changed",) * 4,
    )
    cross_block, cross_block_result = measure_row(
        RowSpec("cross-block-mismatch", "cross-block-mismatch",
                Path("font.ttf"), "U+0041", 12, "classic", "normal", True),
        "cross-block-mismatch",
        {"cangjie": ["cangjie"], "freetype": ["freetype"]},
        None,
        True,
        cross_block_run,
        lambda line: None,
    )
    assert cross_block is not None and "checksum mismatch across blocks" in cross_block
    assert cross_block_result is None
    # Stop before the third block rather than allowing later output to mask a
    # semantically unstable confirmation.
    assert len(cross_block_calls) == 5

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
            RowSpec("command-failure", "command-failure", Path("font.ttf"),
                    "U+0041", 12, "classic", "normal", True),
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


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glyph-bench", type=Path)
    parser.add_argument("--iterations", type=int, default=30000)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--sizes", default="9,16")
    parser.add_argument("--json-output", type=Path)
    parser.add_argument(
        "--extended", action="store_true",
        help="include additional installed-font/script fixtures",
    )
    parser.add_argument(
        "--fail-on-slower", action="store_true",
        help=(
            "fail when any Cangjie row does not meet --minimum-speedup"
        ),
    )
    parser.add_argument(
        "--minimum-speedup",
        type=float,
        default=DEFAULT_MINIMUM_SPEEDUP,
        help=(
            "minimum ratio required by --fail-on-slower "
            f"(default: {DEFAULT_MINIMUM_SPEEDUP:g})"
        ),
    )
    parser.add_argument(
        "--self-test", action="store_true",
        help="run pure retry/aggregation tests without benchmark binaries",
    )
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        print("hinted outline matrix self-tests passed")
        return 0
    if args.glyph_bench is None:
        parser.error("--glyph-bench is required unless --self-test is used")
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    if not valid_minimum_speedup(args.minimum_speedup):
        parser.error("--minimum-speedup must be finite and greater than 1")
    sizes = tuple(int(value) for value in args.sizes.split(","))
    if not sizes or any(value <= 0 for value in sizes):
        parser.error("sizes must be positive integers")
    warmup_iterations = max(1, args.iterations // 10)
    configuration = RunConfiguration(
        glyph_bench=args.glyph_bench,
        iterations=args.iterations,
        samples=args.samples,
        warmup_iterations=warmup_iterations,
        cpu=args.cpu,
        sizes=sizes,
        extended=args.extended,
        fail_on_slower=args.fail_on_slower,
        minimum_speedup=args.minimum_speedup,
    )

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
    manifest: list[RowSpec] = []
    results: list[RowResult] = []
    skipped_rows: list[SkippedRow] = []
    for case in cases:
        if not case.font.is_file():
            parser.error(f"missing fixture: {case.font}")
        for size in sizes:
            for interpreter in interpreters:
                for target in targets:
                    row = row_spec(case, size, interpreter, target)
                    if (
                        not case.system_213_v40_mono_compatible
                        and interpreter == "cleartype"
                        and target == "mono"
                    ):
                        skipped_rows.append(SkippedRow(
                            row,
                            (
                                "system FreeType 2.13.2 mono oracle is "
                                "incompatible with this fixture"
                            ),
                        ))
                        continue
                    manifest.append(row)
                    base = [
                        str(args.glyph_bench), "--mode", "hinted-outline",
                        "--font", str(case.font), "--codepoint", case.codepoint,
                        "--font-size", str(size), "--hinting-target", target,
                        "--hinting-interpreter", interpreter, "--iterations",
                        str(args.iterations), "--warmup",
                        str(warmup_iterations), "--samples",
                        str(args.samples),
                    ]
                    cj = [*base, "--engine", "cangjie"]
                    ft = [*base, "--engine", "freetype"]
                    commands = {"cangjie": cj, "freetype": ft}
                    failure, result = measure_row(
                        row, row.label, commands, args.cpu, args.fail_on_slower,
                        minimum_speedup=args.minimum_speedup,
                    )
                    if result is not None:
                        results.append(result)
                    if failure is not None:
                        failures.append(failure)
    outcome = MatrixOutcome(
        manifest=tuple(manifest),
        results=tuple(results),
        skipped_rows=tuple(skipped_rows),
        failures=tuple(failures),
    )
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    emit_json_report(args.json_output, configuration, outcome)
    print(f"hinted outline matrix: {len(manifest)} semantic rows passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
