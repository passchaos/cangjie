"""Tests for the FreeType matrix report and write-on-success contract."""

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

from tools import run_freetype_matrix as matrix


class FreeTypeMatrixTest(unittest.TestCase):
    case = matrix.Case("synthetic", Path("font.ttf"), "U+0041")

    @staticmethod
    def row(
        *, name: str = "synthetic/face-open", threshold_status: str = "met"
    ) -> matrix.RowResult:
        return matrix.RowResult(
            name=name,
            case=matrix.Case("synthetic", Path("font.ttf"), "U+0041"),
            mode="face-open",
            size=16,
            target_size=32,
            cangjie_checksum_a="aaaa",
            cangjie_checksum_b="aaaa",
            reference_checksum_a="aaaa",
            reference_checksum_b="aaaa",
            semantic_agreement=True,
            cangjie_first_ns_per_iter=4.0,
            cangjie_second_ns_per_iter=1.0,
            reference_first_ns_per_iter=8.0,
            reference_second_ns_per_iter=2.0,
            speedup=2.0 if threshold_status == "met" else 0.9,
            threshold_status=threshold_status,
        )

    @staticmethod
    def fake_record() -> dict[str, str]:
        return {"checksum": "aaaa", "sample_median_ns_per_iter": "4.0"}

    def configuration(
        self, *, fail_on_slower: bool = False
    ) -> matrix.RunConfiguration:
        return matrix.RunConfiguration(
            glyph_bench=Path("bin/glyph-bench"),
            roboto=Path("fonts/Roboto-Regular.ttf"),
            cff=Path("fonts/STIX.otf"),
            cff2=Path("fonts/CFF2.otf"),
            arabic=Path("fonts/Arabic.ttf"),
            cjk=Path("fonts/CJK.ttc"),
            cbdt=None,
            sbix=None,
            colr_v0=None,
            iterations=2,
            samples=3,
            cpu=7,
            sizes=(8, 16),
            minimum_target_size=32,
            fail_on_slower=fail_on_slower,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
        )

    def test_report_contains_manifest_and_a_b_b_a_endpoints(self) -> None:
        row = self.row()
        report = matrix.build_json_report(
            self.configuration(), (row.name,), (row,)
        )
        self.assertEqual(1, report["schema_version"])
        self.assertEqual(
            {"name": matrix.TOOL_NAME, "version": matrix.TOOL_VERSION},
            report["tool"],
        )
        self.assertEqual([row.name], report["manifest"]["rows"])
        self.assertEqual(
            {"a": 4.0, "b": 1.0},
            report["rows"][0]["timing"]["cangjie_ns_per_iter"],
        )
        self.assertTrue(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        json.dumps(report, allow_nan=False)

    def test_report_only_below_threshold_still_marks_success(self) -> None:
        row = self.row(threshold_status="below-minimum")
        report = matrix.build_json_report(
            self.configuration(), (row.name,), (row,)
        )
        self.assertFalse(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])

        enforced = matrix.build_json_report(
            self.configuration(fail_on_slower=True), (row.name,), (row,)
        )
        self.assertFalse(enforced["gate"]["command_succeeded"])

    def test_report_rejects_partial_and_reordered_rows(self) -> None:
        row = self.row()
        with self.assertRaisesRegex(ValueError, "partial matrix"):
            matrix.build_json_report(self.configuration(), (row.name,), ())
        other = self.row(name="other")
        with self.assertRaisesRegex(ValueError, "reordered or mismatched"):
            matrix.build_json_report(
                self.configuration(), (row.name, other.name), (other, row)
            )

    def test_atomic_write_preserves_existing_file_on_failure(self) -> None:
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
                None, self.configuration(), ("synthetic/face-open",), (self.row(),)
            )
        write.assert_not_called()

    def test_main_report_only_run_writes_json(self) -> None:
        def fake_measure_row(*, name: str, **_: object) -> matrix.RowResult:
            return self.row(name=name, threshold_status="below-minimum")

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            stdout = io.StringIO()
            stderr = io.StringIO()
            args = argparse.Namespace(
                glyph_bench=Path("bin/glyph-bench"),
                roboto=Path("fonts/Roboto-Regular.ttf"),
                cff=Path("fonts/STIX.otf"),
                cff2=Path("fonts/CFF2.otf"),
                arabic=Path("fonts/Arabic.ttf"),
                cjk=Path("fonts/CJK.ttc"),
                cbdt=None,
                sbix=None,
                colr_v0=None,
                iterations=2,
                samples=3,
                cpu=None,
                sizes="8,16",
                minimum_target_size=32,
                json_output=destination,
                fail_on_slower=False,
                minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
            )
            with (
                mock.patch.object(matrix.argparse.ArgumentParser, "parse_args", return_value=args),
                mock.patch.object(matrix, "run", return_value=self.fake_record()),
                mock.patch.object(matrix, "measure_row", side_effect=fake_measure_row),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main()
            self.assertEqual(0, status)
            report = json.loads(destination.read_text(encoding="utf-8"))
            self.assertFalse(report["gate"]["thresholds_met"])
            self.assertTrue(report["gate"]["command_succeeded"])
            self.assertIn("Cangjie/FreeType lifecycle matrix completed", stdout.getvalue())
            self.assertEqual("", stderr.getvalue())

    def test_main_enforced_gate_failure_does_not_write_json(self) -> None:
        def fake_measure_row(*, name: str, **_: object) -> matrix.RowResult:
            return self.row(name=name, threshold_status="below-minimum")

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            stderr = io.StringIO()
            args = argparse.Namespace(
                glyph_bench=Path("bin/glyph-bench"),
                roboto=Path("fonts/Roboto-Regular.ttf"),
                cff=Path("fonts/STIX.otf"),
                cff2=Path("fonts/CFF2.otf"),
                arabic=Path("fonts/Arabic.ttf"),
                cjk=Path("fonts/CJK.ttc"),
                cbdt=None,
                sbix=None,
                colr_v0=None,
                iterations=2,
                samples=3,
                cpu=None,
                sizes="8,16",
                minimum_target_size=32,
                json_output=destination,
                fail_on_slower=True,
                minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
            )
            with (
                mock.patch.object(matrix.argparse.ArgumentParser, "parse_args", return_value=args),
                mock.patch.object(matrix, "run", return_value=self.fake_record()),
                mock.patch.object(matrix, "measure_row", side_effect=fake_measure_row),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main()
            self.assertEqual(1, status)
            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertIn("glyf-latin/face-open: performance", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
