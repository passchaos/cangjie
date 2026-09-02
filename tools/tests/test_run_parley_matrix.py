"""Tests for the Parley matrix's process-independent report logic."""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import math
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import run_parley_matrix as matrix


class ParleyMatrixTest(unittest.TestCase):
    case = matrix.Case(
        "latin", Path("fonts/Roboto-Regular.ttf"), Path("texts/latin.txt"),
        "Roboto", "200",
    )
    row = matrix.MatrixRow(
        case=case,
        phase="layout",
        style="default",
        requires_semantic_equality=True,
        requires_object_geometry=False,
    )

    @staticmethod
    def records(
        *,
        cangjie_a: float = 4.0,
        parley_a: float = 8.0,
        parley_b: float = 2.0,
        cangjie_b: float = 1.0,
        glyphs: str = "10",
        lines: str = "2",
        objects: str = "0",
        text_bytes: str = "40",
        geometry_checksum: str = "geom",
        placement_checksum: str = "place",
        object_checksum: str = "object",
        cangjie_checksum: tuple[str, str] = ("cangjie", "cangjie"),
        parley_checksum: tuple[str, str] = ("parley", "parley"),
    ) -> tuple[dict[str, str], ...]:
        base = {
            "text_bytes": text_bytes,
            "glyphs": glyphs,
            "lines": lines,
            "objects": objects,
            "geometry_checksum": geometry_checksum,
            "placement_checksum": placement_checksum,
            "object_checksum": object_checksum,
        }
        return (
            {
                **base,
                "checksum": cangjie_checksum[0],
                "median_ns_per_iter": str(cangjie_a),
            },
            {
                **base,
                "checksum": parley_checksum[0],
                "median_ns_per_iter": str(parley_a),
            },
            {
                **base,
                "checksum": parley_checksum[1],
                "median_ns_per_iter": str(parley_b),
            },
            {
                **base,
                "checksum": cangjie_checksum[1],
                "median_ns_per_iter": str(cangjie_b),
            },
        )

    def configuration(
        self, *, fail_on_slower: bool = False
    ) -> matrix.RunConfiguration:
        return matrix.RunConfiguration(
            cangjie=Path("bin/cangjie"),
            parley_manifest=Path("oracle/Cargo.toml"),
            parley_executable=Path("oracle/target/release/parley-layout-oracle"),
            parley_root=Path("parley"),
            roboto=Path("fonts/Roboto-Regular.ttf"),
            arabic_font=Path("fonts/NotoKufiArabic-Regular.ttf"),
            japanese_font=Path("fonts/NotoSansCJKjp-Regular.otf"),
            bidi_font=Path("fonts/DejaVuSans.ttf"),
            bidi_family="DejaVu Sans",
            fallback_font=Path("fonts/NotoSansDevanagari-Regular.ttf"),
            iterations=2,
            samples=3,
            cpu=7,
            fail_on_slower=fail_on_slower,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
            parley_vertical_api=False,
        )

    def test_build_matrix_rows_matches_current_38_row_manifest(self) -> None:
        args = argparse.Namespace(
            parley_root=Path("parley-root"),
            roboto=Path("fonts/Roboto-Regular.ttf"),
            arabic_font=Path("fonts/NotoKufiArabic-Regular.ttf"),
            japanese_font=Path("fonts/NotoSansCJKjp-Regular.otf"),
            bidi_font=Path("fonts/DejaVuSans.ttf"),
            bidi_family="DejaVu Sans",
            fallback_font=Path("fonts/NotoSansDevanagari-Regular.ttf"),
        )

        rows = matrix.build_matrix_rows(args)

        self.assertEqual(38, len(rows))
        self.assertEqual("latin/layout/default", rows[0].identifier)
        self.assertEqual("latin/layout/center", rows[1].identifier)
        self.assertEqual("latin/reflow/center", rows[2].identifier)
        self.assertEqual("fallback/reflow/fallback", rows[-1].identifier)
        self.assertEqual(
            [
                "latin/layout/default",
                "latin/layout/center",
                "latin/reflow/center",
                "latin/layout/spacing",
                "latin/layout/alternating",
                "latin/reflow/default",
                "latin/layout/inline-object",
                "latin/reflow/inline-object",
                "latin/layout/out-of-flow-object",
                "latin/reflow/out-of-flow-object",
                "latin/layout/custom-out-of-flow-object",
                "latin/reflow/custom-out-of-flow-object",
            ],
            [row.identifier for row in rows[:12]],
        )
        self.assertFalse(rows[6].requires_semantic_equality)
        self.assertTrue(rows[6].requires_object_geometry)
        self.assertTrue(rows[1].requires_semantic_equality)

    def test_evaluate_row_records_endpoints_and_equivalence(self) -> None:
        result, failures = matrix.evaluate_row(
            self.row,
            self.records(),
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )

        self.assertEqual((), failures)
        self.assertEqual((4.0, 1.0), (
            result.cangjie_a_median_ns_per_iter,
            result.cangjie_b_median_ns_per_iter,
        ))
        self.assertEqual((8.0, 2.0), (
            result.parley_a_median_ns_per_iter,
            result.parley_b_median_ns_per_iter,
        ))
        self.assertEqual(2.0, result.cangjie_geometric_mean_ns_per_iter)
        self.assertEqual(4.0, result.parley_geometric_mean_ns_per_iter)
        self.assertEqual(2.0, result.speedup)
        self.assertEqual("met", result.threshold_status)
        self.assertTrue(result.geometry_equal)
        self.assertTrue(result.placement_equal)
        self.assertTrue(result.object_geometry_equal)
        self.assertTrue(result.cangjie_checksum_stable)
        self.assertTrue(result.parley_checksum_stable)

    def test_report_contains_configuration_manifest_and_rows(self) -> None:
        result, failures = matrix.evaluate_row(
            self.row,
            self.records(),
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        report = matrix.build_json_report(
            self.configuration(), (self.row,), (result,), failures
        )

        self.assertEqual(1, report["schema_version"])
        self.assertEqual(
            {"name": matrix.TOOL_NAME, "version": matrix.TOOL_VERSION},
            report["tool"],
        )
        self.assertEqual(2, report["config"]["iterations"])
        self.assertEqual(3, report["config"]["samples"])
        self.assertEqual(7, report["config"]["cpu"])
        self.assertFalse(report["config"]["fail_on_slower"])
        self.assertFalse(report["config"]["parley_vertical_api"])
        self.assertEqual(1, report["manifest"]["row_count"])
        self.assertEqual(["latin/layout/default"], [
            row["id"] for row in report["manifest"]["rows"]
        ])
        row = report["rows"][0]
        self.assertEqual(
            {"cangjie": {"a": 4.0, "b": 1.0}, "parley": {"a": 8.0, "b": 2.0}},
            row["timings_ns_per_iter"]["endpoint_medians"],
        )
        self.assertEqual(
            {"geometry": True, "placement": True, "object_geometry": True,
             "cangjie_native_stable": True, "parley_native_stable": True},
            row["equalities"],
        )
        self.assertEqual(2.0, row["speedup"])
        self.assertEqual("met", row["threshold_status"])
        self.assertTrue(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        self.assertEqual([], report["summary"]["below_minimum_rows"])
        self.assertEqual([], report["summary"]["failures"])
        json.dumps(report, allow_nan=False)

    def test_report_only_below_threshold_is_successful(self) -> None:
        result, failures = matrix.evaluate_row(
            self.row,
            self.records(cangjie_a=4.0, parley_a=3.0, parley_b=3.0, cangjie_b=4.0),
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        report = matrix.build_json_report(
            self.configuration(), (self.row,), (result,), failures
        )

        self.assertEqual("below-minimum", report["rows"][0]["threshold_status"])
        self.assertFalse(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        self.assertEqual(
            ["latin/layout/default"], report["summary"]["below_minimum_rows"]
        )

        enforced = matrix.build_json_report(
            self.configuration(fail_on_slower=True), (self.row,), (result,), failures
        )
        self.assertFalse(enforced["gate"]["command_succeeded"])

    def test_report_rejects_partial_matrix(self) -> None:
        with self.assertRaisesRegex(ValueError, "partial matrix"):
            matrix.build_json_report(self.configuration(), (self.row,), (), ())

    def test_atomic_write_replaces_destination_and_leaves_no_temp(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            report = {"schema_version": 1, "value": 2.5}

            matrix.write_json_atomic(destination, report)

            self.assertEqual(report, json.loads(destination.read_text()))
            self.assertEqual([], list(root.glob(".matrix.json.*.tmp")))

    def test_atomic_write_keeps_existing_file_on_serialization_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "matrix.json"
            destination.write_text("old", encoding="utf-8")

            with self.assertRaises(ValueError):
                matrix.write_json_atomic(destination, {"bad": math.nan})

            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertEqual([], list(root.glob(".matrix.json.*.tmp")))

    def test_no_json_path_performs_no_write(self) -> None:
        outcome = matrix.MatrixOutcome((self.row,), (), ())
        with mock.patch.object(matrix, "write_json_atomic") as write:
            matrix.emit_json_report(None, self.configuration(), outcome)
        write.assert_not_called()

    def test_main_execution_failure_leaves_destination_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            with (
                mock.patch.object(subprocess, "run"),
                mock.patch.object(
                    matrix, "run_matrix", side_effect=RuntimeError("boom")
                ),
                mock.patch.object(Path, "is_file", return_value=True),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                with self.assertRaisesRegex(RuntimeError, "boom"):
                    matrix.main(
                        [
                            "--cangjie", "cangjie",
                            "--parley-manifest", "oracle/Cargo.toml",
                            "--parley-root", "parley",
                            "--roboto", "roboto.ttf",
                            "--arabic-font", "arabic.ttf",
                            "--japanese-font", "japanese.ttf",
                            "--json-output", str(destination),
                        ]
                    )

            self.assertEqual("old", destination.read_text(encoding="utf-8"))

    def test_main_does_not_write_report_for_enforced_gate_failure(self) -> None:
        result, _ = matrix.evaluate_row(
            self.row,
            self.records(cangjie_a=4.0, parley_a=3.0, parley_b=3.0, cangjie_b=4.0),
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        outcome = matrix.MatrixOutcome(
            (self.row,),
            (result,),
            ("latin/layout/default: speedup 0.750000x is below the 1.010000x minimum",),
        )
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            stdout = io.StringIO()
            stderr = io.StringIO()
            with (
                mock.patch.object(subprocess, "run"),
                mock.patch.object(matrix, "run_matrix", return_value=outcome),
                mock.patch.object(Path, "is_file", return_value=True),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main(
                    [
                        "--cangjie", "cangjie",
                        "--parley-manifest", "oracle/Cargo.toml",
                        "--parley-root", "parley",
                        "--roboto", "roboto.ttf",
                        "--arabic-font", "arabic.ttf",
                        "--japanese-font", "japanese.ttf",
                        "--iterations", "2",
                        "--samples", "3",
                        "--fail-on-slower",
                        "--json-output", str(destination),
                    ]
                )

            self.assertEqual(1, status)
            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertEqual(
                "parley_performance_gate=enforced minimum_speedup=1.010000x\n",
                stdout.getvalue(),
            )
            self.assertEqual(
                "Cangjie/Parley matrix failed (minimum_speedup=1.010000x):\n"
                "- latin/layout/default: speedup 0.750000x is below the "
                "1.010000x minimum\n",
                stderr.getvalue(),
            )

    def test_main_writes_report_for_successful_report_only_run(self) -> None:
        result, failures = matrix.evaluate_row(
            self.row,
            self.records(cangjie_a=4.0, parley_a=3.0, parley_b=3.0, cangjie_b=4.0),
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        outcome = matrix.MatrixOutcome((self.row,), (result,), failures)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            stdout = io.StringIO()
            stderr = io.StringIO()
            with (
                mock.patch.object(subprocess, "run"),
                mock.patch.object(matrix, "run_matrix", return_value=outcome),
                mock.patch.object(Path, "is_file", return_value=True),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main(
                    [
                        "--cangjie", "cangjie",
                        "--parley-manifest", "oracle/Cargo.toml",
                        "--parley-root", "parley",
                        "--roboto", "roboto.ttf",
                        "--arabic-font", "arabic.ttf",
                        "--japanese-font", "japanese.ttf",
                        "--iterations", "2",
                        "--samples", "3",
                        "--json-output", str(destination),
                    ]
                )

            self.assertEqual(0, status)
            report = json.loads(destination.read_text(encoding="utf-8"))
            self.assertEqual("report-only", report["gate"]["mode"])
            self.assertFalse(report["gate"]["thresholds_met"])
            self.assertTrue(report["gate"]["command_succeeded"])
            self.assertEqual(
                "parley_performance_gate=report-only minimum_speedup=1.010000x\n"
                "Cangjie/Parley output-count, proven text-semantics, and "
                "object-geometry matrix passed: 1 cases gate_mode=report-only "
                "minimum_speedup=1.010000x\n"
                "parley_vertical_api=false\n",
                stdout.getvalue(),
            )
            self.assertEqual("", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
