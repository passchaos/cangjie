"""Tests for hinted-outline matrix reporting and JSON artifact handling."""

from __future__ import annotations

import contextlib
import io
import json
import math
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import run_hinted_outline_matrix as hinted


class HintedOutlineMatrixJsonTest(unittest.TestCase):
    def configuration(
        self, *, fail_on_slower: bool = False
    ) -> hinted.RunConfiguration:
        return hinted.RunConfiguration(
            glyph_bench=Path("bin/glyph-bench"),
            iterations=300,
            samples=7,
            warmup_iterations=30,
            cpu=4,
            sizes=(9, 16),
            extended=True,
            fail_on_slower=fail_on_slower,
            minimum_speedup=hinted.DEFAULT_MINIMUM_SPEEDUP,
        )

    def row(self, label: str = "latin-a/9/classic/normal") -> hinted.RowSpec:
        return hinted.RowSpec(
            label=label,
            case_name="latin-a",
            font=Path("/fonts/DejaVuSans.ttf"),
            codepoint="U+0041",
            size=9,
            interpreter="classic",
            target="normal",
            system_213_v40_mono_compatible=True,
        )

    def row_result(
        self,
        *,
        label: str = "latin-a/9/classic/normal",
        speedup: float = 1.25,
        final_gate_status: str = "met",
        confirmation_status: str = "not-needed",
        checksum: str = "same",
    ) -> hinted.RowResult:
        row = self.row(label)
        timing = hinted.TimingBlock(
            cangjie_ns=4.0,
            freetype_ns=4.0 * speedup,
            raw_cangjie_ns=(4.0, 4.0),
            raw_freetype_ns=(4.0 * speedup, 4.0 * speedup),
            checksum=checksum,
        )
        return hinted.RowResult(
            row=row,
            blocks=(
                hinted.BlockResult(
                    index=1,
                    order_label="ABBA",
                    order=hinted.BLOCK_ORDERS[0],
                    timing=timing,
                ),
            ),
            aggregate_speedup=speedup,
            final_gate_status=final_gate_status,
            confirmation_status=confirmation_status,
        )

    def test_report_contains_run_manifest_rows_and_gate(self) -> None:
        outcome = hinted.MatrixOutcome(
            manifest=(self.row(),),
            results=(self.row_result(),),
            skipped_rows=(
                hinted.SkippedRow(
                    hinted.RowSpec(
                        label="latin-a/9/cleartype/mono",
                        case_name="latin-a",
                        font=Path("/fonts/DejaVuSans.ttf"),
                        codepoint="U+0041",
                        size=9,
                        interpreter="cleartype",
                        target="mono",
                        system_213_v40_mono_compatible=False,
                    ),
                    "fixture is incompatible with the system mono oracle",
                ),
            ),
            failures=(),
        )

        report = hinted.build_json_report(self.configuration(), outcome)

        self.assertEqual(1, report["schema_version"])
        self.assertEqual(
            {"name": hinted.TOOL_NAME, "version": hinted.TOOL_VERSION},
            report["tool"],
        )
        self.assertEqual("bin/glyph-bench", report["run"]["glyph_bench"])
        self.assertEqual([9, 16], report["run"]["sizes"])
        self.assertTrue(report["run"]["extended"])
        self.assertEqual(
            [list(order) for order in hinted.BLOCK_ORDERS],
            report["run"]["block_orders"],
        )
        self.assertEqual(
            ["latin-a/9/classic/normal"],
            [row["label"] for row in report["manifest"]["rows"]],
        )
        self.assertEqual(
            ["latin-a/9/cleartype/mono"],
            [row["label"] for row in report["manifest"]["skipped_rows"]],
        )
        self.assertEqual(
            "fixture is incompatible with the system mono oracle",
            report["manifest"]["skipped_rows"][0]["reason"],
        )
        self.assertEqual("met", report["rows"][0]["final_gate_status"])
        self.assertEqual("not-needed", report["rows"][0]["confirmation_status"])
        self.assertEqual("same", report["rows"][0]["blocks"][0]["checksum"])
        self.assertTrue(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        json.dumps(report, allow_nan=False)

    def test_report_only_below_threshold_is_still_command_success(self) -> None:
        outcome = hinted.MatrixOutcome(
            manifest=(self.row(),),
            results=(
                self.row_result(
                    speedup=0.75,
                    final_gate_status="below-minimum",
                    confirmation_status="not-needed",
                ),
            ),
            skipped_rows=(),
            failures=(),
        )

        report = hinted.build_json_report(self.configuration(), outcome)

        self.assertEqual("report-only", report["gate"]["mode"])
        self.assertFalse(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        self.assertEqual(
            ["latin-a/9/classic/normal"], report["summary"]["below_minimum_rows"]
        )

        enforced = hinted.build_json_report(
            self.configuration(fail_on_slower=True), outcome
        )
        self.assertEqual("enforced", enforced["gate"]["mode"])
        self.assertFalse(enforced["gate"]["command_succeeded"])

    def test_report_rejects_partial_or_failing_matrix(self) -> None:
        row = self.row()
        result = self.row_result()
        with self.assertRaisesRegex(ValueError, "partial"):
            hinted.build_json_report(
                self.configuration(),
                hinted.MatrixOutcome(
                    manifest=(row,),
                    results=(),
                    skipped_rows=(),
                    failures=(),
                ),
            )
        with self.assertRaisesRegex(ValueError, "failing matrix"):
            hinted.build_json_report(
                self.configuration(fail_on_slower=True),
                hinted.MatrixOutcome(
                    manifest=(row,),
                    results=(result,),
                    skipped_rows=(),
                    failures=("latin-a: below minimum",),
                ),
            )

    def test_atomic_write_replaces_destination_and_cleans_temp(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            report = {"schema_version": 1, "value": 2.5}

            hinted.write_json_atomic(destination, report)

            self.assertEqual(report, json.loads(destination.read_text()))
            self.assertEqual([], list(root.glob(".matrix.json.*.tmp")))

    def test_atomic_write_preserves_existing_file_on_serialization_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "matrix.json"
            destination.write_text("old", encoding="utf-8")

            with self.assertRaises(ValueError):
                hinted.write_json_atomic(destination, {"bad": math.nan})

            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertEqual([], list(root.glob(".matrix.json.*.tmp")))

    def test_main_execution_failure_does_not_write_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")

            with (
                mock.patch.object(Path, "is_file", return_value=True),
                mock.patch.object(
                    hinted, "measure_row", side_effect=RuntimeError("boom")
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaisesRegex(RuntimeError, "boom"):
                    hinted.main(
                        [
                            "--glyph-bench", "glyph-bench",
                            "--sizes", "9",
                            "--json-output", str(destination),
                        ]
                    )

            self.assertEqual("old", destination.read_text(encoding="utf-8"))

    def test_main_enforced_gate_failure_does_not_write_json(self) -> None:
        def fake_measure_row(
            row: hinted.RowSpec,
            label: str,
            commands: dict[str, list[str]],
            cpu: int | None,
            strict: bool,
            run_command=hinted.run,
            emit=print,
            minimum_speedup: float = hinted.DEFAULT_MINIMUM_SPEEDUP,
        ) -> tuple[str | None, hinted.RowResult | None]:
            del commands, cpu, run_command, emit, minimum_speedup
            result = self.row_result(
                label=label,
                speedup=0.8,
                final_gate_status="below-minimum",
                confirmation_status="fail" if strict else "not-needed",
            )
            failure = (
                f"{label}: performance aggregate_speedup=0.800x "
                f"blocks=3 minimum_speedup={hinted.DEFAULT_MINIMUM_SPEEDUP:.3f}x"
            )
            return failure, result

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            stdout = io.StringIO()

            with (
                mock.patch.object(Path, "is_file", return_value=True),
                mock.patch.object(hinted, "measure_row", side_effect=fake_measure_row),
                contextlib.redirect_stdout(stdout),
            ):
                status = hinted.main(
                    [
                        "--glyph-bench", "glyph-bench",
                        "--sizes", "9",
                        "--fail-on-slower",
                        "--json-output", str(destination),
                    ]
                )

            self.assertEqual(1, status)
            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertIn("FAIL: latin-a/9/classic/normal", stdout.getvalue())

    def test_main_report_only_completion_writes_json(self) -> None:
        def fake_measure_row(
            row: hinted.RowSpec,
            label: str,
            commands: dict[str, list[str]],
            cpu: int | None,
            strict: bool,
            run_command=hinted.run,
            emit=print,
            minimum_speedup: float = hinted.DEFAULT_MINIMUM_SPEEDUP,
        ) -> tuple[str | None, hinted.RowResult | None]:
            del commands, cpu, run_command, emit, minimum_speedup, strict
            return (
                None,
                self.row_result(
                    label=label,
                    speedup=0.8,
                    final_gate_status="below-minimum",
                ),
            )

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            stdout = io.StringIO()

            with (
                mock.patch.object(Path, "is_file", return_value=True),
                mock.patch.object(hinted, "measure_row", side_effect=fake_measure_row),
                contextlib.redirect_stdout(stdout),
            ):
                status = hinted.main(
                    [
                        "--glyph-bench", "glyph-bench",
                        "--sizes", "9",
                        "--json-output", str(destination),
                    ]
                )

            self.assertEqual(0, status)
            report = json.loads(destination.read_text(encoding="utf-8"))
            self.assertEqual("report-only", report["gate"]["mode"])
            self.assertFalse(report["gate"]["thresholds_met"])
            self.assertTrue(report["gate"]["command_succeeded"])
            self.assertEqual(60, report["summary"]["executed_row_count"])
            self.assertEqual(
                "hinted outline matrix: 60 semantic rows passed\n",
                stdout.getvalue(),
            )


if __name__ == "__main__":
    unittest.main()
