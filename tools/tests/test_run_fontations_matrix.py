"""Tests for the Fontations matrix report and row accounting helpers."""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import math
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import run_fontations_matrix as matrix


class FontationsMatrixTest(unittest.TestCase):
    base_case = matrix.Case("synthetic", "outline-session", "font.ttf", 7)

    @staticmethod
    def row(
        *,
        name: str = "synthetic",
        speedup: float = 2.0,
        threshold_status: str = "met",
        semantic_agreement: bool = True,
    ) -> matrix.RowResult:
        case = matrix.Case(name, "outline-session", "font.ttf", 7)
        return matrix.RowResult(
            case=case,
            resolved_font=Path("fixtures/font.ttf"),
            semantic_cangjie_checksum="aaaa",
            semantic_reference_checksum="aaaa" if semantic_agreement else "bbbb",
            semantic_agreement=semantic_agreement,
            cangjie_first_ns_per_iter=4.0,
            cangjie_second_ns_per_iter=1.0,
            reference_first_ns_per_iter=8.0,
            reference_second_ns_per_iter=2.0,
            speedup=speedup,
            threshold_status=threshold_status,
        )

    @staticmethod
    def row_for_case(
        case: matrix.Case,
        *,
        speedup: float = 2.0,
        threshold_status: str = "met",
        semantic_agreement: bool = True,
    ) -> matrix.RowResult:
        return matrix.RowResult(
            case=case,
            resolved_font=Path("fixtures") / case.font,
            semantic_cangjie_checksum="aaaa",
            semantic_reference_checksum="aaaa" if semantic_agreement else "bbbb",
            semantic_agreement=semantic_agreement,
            cangjie_first_ns_per_iter=4.0,
            cangjie_second_ns_per_iter=1.0,
            reference_first_ns_per_iter=8.0,
            reference_second_ns_per_iter=2.0,
            speedup=speedup,
            threshold_status=threshold_status,
        )

    def configuration(
        self, *, fail_on_slower: bool = False
    ) -> matrix.RunConfiguration:
        return matrix.RunConfiguration(
            cangjie=Path("bin/cangjie"),
            skrifa_manifest=Path("oracle/Cargo.toml"),
            skrifa_executable=Path("oracle/target/release/fontations-bitmap-oracle"),
            fixture_dir=Path("fixtures"),
            roboto=Path("fonts/Roboto-Regular.ttf"),
            cff2=Path("fonts/CFF2.otf"),
            varc=Path("fonts/varc.ttf"),
            cff2_extended=Path("fonts/extended.otf"),
            extended=False,
            source="all",
            iterations=2,
            samples=3,
            cpu=7,
            fail_on_slower=fail_on_slower,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
        )

    def test_report_contains_manifest_and_threshold_summary(self) -> None:
        row = self.row()
        report = matrix.build_json_report(
            self.configuration(), (row.case,), (row,)
        )
        self.assertEqual(1, report["schema_version"])
        self.assertEqual(
            {"name": matrix.TOOL_NAME, "version": matrix.TOOL_VERSION},
            report["tool"],
        )
        self.assertEqual(["synthetic"], report["manifest"]["rows"])
        self.assertTrue(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["semantic_agreement"])
        self.assertTrue(report["gate"]["command_succeeded"])
        self.assertEqual(
            {"a": 4.0, "b": 1.0},
            report["rows"][0]["timing"]["cangjie_ns_per_iter"],
        )
        json.dumps(report, allow_nan=False)

    def test_report_only_below_threshold_still_succeeds(self) -> None:
        row = self.row(speedup=0.9, threshold_status="below-minimum")
        report = matrix.build_json_report(
            self.configuration(), (row.case,), (row,)
        )
        self.assertFalse(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        self.assertEqual(["synthetic"], report["summary"]["below_minimum_rows"])

        enforced = matrix.build_json_report(
            self.configuration(fail_on_slower=True), (row.case,), (row,)
        )
        self.assertFalse(enforced["gate"]["command_succeeded"])

    def test_report_rejects_partial_or_reordered_results(self) -> None:
        row = self.row()
        with self.assertRaisesRegex(ValueError, "partial matrix"):
            matrix.build_json_report(self.configuration(), (row.case,), ())
        other = self.row(name="other")
        with self.assertRaisesRegex(ValueError, "reordered or mismatched"):
            matrix.build_json_report(
                self.configuration(), (row.case, other.case), (other, row)
            )

    def test_atomic_write_replaces_destination_and_keeps_existing_file_on_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            matrix.write_json_atomic(destination, {"schema_version": 1})
            self.assertEqual(
                {"schema_version": 1},
                json.loads(destination.read_text(encoding="utf-8")),
            )
            with self.assertRaises(ValueError):
                matrix.write_json_atomic(destination, {"bad": math.nan})
            self.assertEqual(
                {"schema_version": 1},
                json.loads(destination.read_text(encoding="utf-8")),
            )

    def test_emit_json_report_is_noop_without_destination(self) -> None:
        with mock.patch.object(matrix, "write_json_atomic") as write:
            matrix.emit_json_report(
                None, self.configuration(), (self.base_case,), (self.row(),)
            )
        write.assert_not_called()

    def test_main_success_writes_report_only_after_complete_run(self) -> None:
        def fake_measure_case(*, case: matrix.Case, **_: object) -> matrix.RowResult:
            return self.row_for_case(
                case, speedup=0.9, threshold_status="below-minimum"
            )

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            stdout = io.StringIO()
            stderr = io.StringIO()
            args = argparse.Namespace(
                cangjie=Path("bin/cangjie"),
                skrifa_manifest=Path("oracle/Cargo.toml"),
                fixture_dir=Path("fixtures"),
                roboto=Path("fonts/Roboto-Regular.ttf"),
                cff2=Path("fonts/CFF2.otf"),
                varc=Path("fonts/varc.ttf"),
                cff2_extended=Path("fonts/extended.otf"),
                extended=False,
                iterations=2,
                samples=3,
                cpu=None,
                json_output=destination,
                source="all",
                fail_on_slower=False,
                minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
            )
            with (
                mock.patch.object(matrix.argparse.ArgumentParser, "parse_args", return_value=args),
                mock.patch.object(matrix.subprocess, "run"),
                mock.patch.object(matrix, "run", side_effect=AssertionError("runner should be mocked")),
                mock.patch.object(matrix, "case_font", return_value=Path("fixtures/font.ttf")),
                mock.patch.object(matrix, "measure_case", side_effect=fake_measure_case),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main()
            self.assertEqual(0, status)
            report = json.loads(destination.read_text(encoding="utf-8"))
            self.assertFalse(report["gate"]["thresholds_met"])
            self.assertTrue(report["gate"]["command_succeeded"])
            self.assertIn("Fontations/Skrifa matrix passed: 33 cases", stdout.getvalue())
            self.assertEqual("", stderr.getvalue())

    def test_main_enforced_gate_failure_leaves_destination_untouched(self) -> None:
        def fake_measure_case(*, case: matrix.Case, **_: object) -> matrix.RowResult:
            return self.row_for_case(
                case, speedup=0.9, threshold_status="below-minimum"
            )

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            stderr = io.StringIO()
            args = argparse.Namespace(
                cangjie=Path("bin/cangjie"),
                skrifa_manifest=Path("oracle/Cargo.toml"),
                fixture_dir=Path("fixtures"),
                roboto=Path("fonts/Roboto-Regular.ttf"),
                cff2=Path("fonts/CFF2.otf"),
                varc=Path("fonts/varc.ttf"),
                cff2_extended=Path("fonts/extended.otf"),
                extended=False,
                iterations=2,
                samples=3,
                cpu=None,
                json_output=destination,
                source="all",
                fail_on_slower=True,
                minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
            )
            with (
                mock.patch.object(matrix.argparse.ArgumentParser, "parse_args", return_value=args),
                mock.patch.object(matrix.subprocess, "run"),
                mock.patch.object(matrix, "case_font", return_value=Path("fixtures/font.ttf")),
                mock.patch.object(matrix, "measure_case", side_effect=fake_measure_case),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main()
            self.assertEqual(1, status)
            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertIn("synthetic: performance", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
