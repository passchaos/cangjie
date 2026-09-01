"""Tests for the shaping matrix's process-independent report logic."""

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

from tools import run_shaping_performance_matrix as matrix


class ShapingPerformanceMatrixTest(unittest.TestCase):
    case = matrix.Case(
        "synthetic", "font.ttf", "text.txt", "ltr",
        ("--language", "dflt"),
    )

    @staticmethod
    def records(
        medians: tuple[float, float, float, float, float, float],
        *,
        normalized_glyphs: int = 10,
        iterations: int = 2,
        samples: int = 3,
    ) -> tuple[dict[str, str], ...]:
        records: list[dict[str, str]] = []
        for index, value in enumerate(medians):
            aggregate = index not in (2, 3)
            glyphs = (
                normalized_glyphs * iterations * samples
                if aggregate
                else normalized_glyphs
            )
            key = (
                "sample_median_ns_per_glyph"
                if aggregate
                else "median_ns_per_glyph"
            )
            records.append({key: str(value), "glyphs": str(glyphs)})
        return tuple(records)

    def configuration(
        self, *, fail_on_slower: bool = False
    ) -> matrix.RunConfiguration:
        return matrix.RunConfiguration(
            cangjie=Path("bin/cangjie"),
            harfbuzz=Path("bin/harfbuzz"),
            harfrust_manifest=Path("oracle/Cargo.toml"),
            harfrust_executable=Path("oracle/target/release/oracle"),
            corpus_root=Path("corpus"),
            suite="core",
            iterations=2,
            samples=3,
            cpu=7,
            fail_on_slower=fail_on_slower,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
        )

    def test_evaluate_case_records_endpoints_means_and_semantics(self) -> None:
        # Symmetric record order is C/H/R/R/H/C. These values make HarfBuzz
        # the fastest reference and keep every calculation exact.
        result = matrix.evaluate_case(
            self.case,
            self.records((4.0, 8.0, 18.0, 8.0, 2.0, 1.0)),
            iterations=2,
            samples=3,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
        )

        self.assertEqual(
            (4.0, 1.0),
            (
                result.cangjie.a_median_ns_per_glyph,
                result.cangjie.b_median_ns_per_glyph,
            ),
        )
        self.assertEqual(2.0, result.cangjie.geometric_mean_ns_per_glyph)
        self.assertEqual(4.0, result.harfbuzz.geometric_mean_ns_per_glyph)
        self.assertEqual(12.0, result.harfrust.geometric_mean_ns_per_glyph)
        self.assertEqual("harfbuzz", result.fastest_reference)
        self.assertEqual(2.0, result.speedup_vs_fastest_reference)
        self.assertEqual("met", result.threshold_status)
        self.assertEqual(10, result.normalized_glyph_count)
        self.assertTrue(result.semantic_count_agreement)
        self.assertEqual(
            (10, 10),
            (
                result.harfrust.a_normalized_glyph_count,
                result.harfrust.b_normalized_glyph_count,
            ),
        )

    def test_evaluate_case_rejects_semantic_count_disagreement(self) -> None:
        records = list(self.records((1.0, 2.0, 3.0, 3.0, 2.0, 1.0)))
        records[3]["glyphs"] = "11"
        with self.assertRaisesRegex(RuntimeError, "glyph counts"):
            matrix.evaluate_case(
                self.case, records, 2, 3, matrix.DEFAULT_MINIMUM_SPEEDUP
            )

    def test_reference_tie_uses_harfbuzz_deterministically(self) -> None:
        result = matrix.evaluate_case(
            self.case,
            self.records((2.0, 4.0, 8.0, 2.0, 1.0, 2.0)),
            2,
            3,
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        self.assertEqual("harfbuzz", result.fastest_reference)

    def test_report_contains_configuration_and_auditable_results(self) -> None:
        result = matrix.evaluate_case(
            self.case,
            self.records((4.0, 8.0, 18.0, 8.0, 2.0, 1.0)),
            2,
            3,
            matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        report = matrix.build_json_report(
            self.configuration(), (self.case,), (result,)
        )

        self.assertEqual(1, report["schema_version"])
        self.assertEqual(
            {"name": matrix.TOOL_NAME, "version": matrix.TOOL_VERSION},
            report["tool"],
        )
        self.assertEqual("core", report["run"]["suite"])
        self.assertEqual(2, report["run"]["iterations"])
        self.assertEqual(3, report["run"]["samples"])
        self.assertEqual(7, report["run"]["cpu"])
        self.assertFalse(report["run"]["fail_on_slower"])
        self.assertEqual(
            matrix.DEFAULT_MINIMUM_SPEEDUP,
            report["run"]["minimum_speedup"],
        )
        self.assertEqual(
            list(matrix.EXECUTION_ORDER), report["run"]["execution_order"]
        )
        self.assertEqual(["synthetic"], report["suite"]["cases"])
        row = report["cases"][0]
        self.assertEqual(
            {"a": 4.0, "b": 1.0},
            row["engines"]["cangjie"]["endpoint_medians_ns_per_glyph"],
        )
        self.assertEqual(
            2.0, row["engines"]["cangjie"]["geometric_mean_ns_per_glyph"]
        )
        self.assertEqual("harfbuzz", row["fastest_reference"]["engine"])
        self.assertEqual(2.0, row["speedup_vs_fastest_reference"])
        self.assertEqual(10, row["normalized_glyph_count"])
        self.assertTrue(row["semantic_count_agreement"])
        self.assertTrue(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        json.dumps(report, allow_nan=False)

    def test_report_only_below_threshold_is_successful(self) -> None:
        result = matrix.evaluate_case(
            self.case, self.records((4.0, 3.0, 8.0, 2.0, 3.0, 4.0)),
            2, 3, matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        report = matrix.build_json_report(
            self.configuration(), (self.case,), (result,)
        )
        self.assertEqual("below-minimum", report["cases"][0]["threshold_status"])
        self.assertFalse(report["gate"]["thresholds_met"])
        self.assertTrue(report["gate"]["command_succeeded"])
        self.assertEqual(
            ["synthetic"], report["summary"]["below_minimum_cases"]
        )

        enforced = matrix.build_json_report(
            self.configuration(fail_on_slower=True),
            (self.case,),
            (result,),
        )
        self.assertFalse(enforced["gate"]["command_succeeded"])

    def test_report_rejects_partial_matrix(self) -> None:
        with self.assertRaisesRegex(ValueError, "partial matrix"):
            matrix.build_json_report(self.configuration(), (self.case,), ())

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

    def test_incomplete_execution_aborts_without_an_outcome(self) -> None:
        args = argparse.Namespace(
            suite="core", cangjie=Path("cangjie"),
            harfbuzz=Path("harfbuzz"), corpus_root=Path("corpus"),
            iterations=2, samples=3, cpu=None, fail_on_slower=False,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        with mock.patch.object(matrix, "run", side_effect=RuntimeError("boom")):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                matrix.run_matrix(args, Path("harfrust"))

    def test_no_json_path_performs_no_write(self) -> None:
        outcome = matrix.MatrixOutcome((self.case,), (), ())
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
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                with self.assertRaisesRegex(RuntimeError, "boom"):
                    matrix.main(
                        [
                            "--cangjie", "cangjie",
                            "--harfbuzz", "harfbuzz",
                            "--harfrust-manifest", "oracle/Cargo.toml",
                            "--corpus-root", "corpus",
                            "--json-output", str(destination),
                        ]
                    )

            self.assertEqual("old", destination.read_text(encoding="utf-8"))

    def test_main_does_not_write_report_for_enforced_gate_failure(self) -> None:
        failing_result = matrix.evaluate_case(
            self.case, self.records((4.0, 3.0, 8.0, 2.0, 3.0, 4.0)),
            2, 3, matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        outcome = matrix.MatrixOutcome(
            (self.case,),
            (failing_result,),
            ("synthetic: below minimum",),
        )
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            destination.write_text("old", encoding="utf-8")
            stdout = io.StringIO()
            stderr = io.StringIO()
            with (
                mock.patch.object(subprocess, "run"),
                mock.patch.object(matrix, "run_matrix", return_value=outcome),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main(
                    [
                        "--cangjie", "cangjie",
                        "--harfbuzz", "harfbuzz",
                        "--harfrust-manifest", "oracle/Cargo.toml",
                        "--corpus-root", "corpus",
                        "--iterations", "2",
                        "--samples", "3",
                        "--fail-on-slower",
                        "--json-output", str(destination),
                    ]
                )

            self.assertEqual(1, status)
            self.assertEqual("old", destination.read_text(encoding="utf-8"))
            self.assertEqual(
                "shaping_performance_gate=enforced "
                "minimum_speedup=1.010000x\n",
                stdout.getvalue(),
            )
            self.assertEqual(
                "Cangjie shaping performance matrix failed "
                "(minimum_speedup=1.010000x):\n"
                "- synthetic: below minimum\n",
                stderr.getvalue(),
            )

    def test_main_writes_report_for_successful_report_only_run(self) -> None:
        result = matrix.evaluate_case(
            self.case, self.records((4.0, 3.0, 8.0, 2.0, 3.0, 4.0)),
            2, 3, matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        outcome = matrix.MatrixOutcome((self.case,), (result,), ())
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "matrix.json"
            stdout = io.StringIO()
            stderr = io.StringIO()
            with (
                mock.patch.object(subprocess, "run"),
                mock.patch.object(matrix, "run_matrix", return_value=outcome),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                status = matrix.main(
                    [
                        "--cangjie", "cangjie",
                        "--harfbuzz", "harfbuzz",
                        "--harfrust-manifest", "oracle/Cargo.toml",
                        "--corpus-root", "corpus",
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
                "shaping_performance_gate=report-only "
                "minimum_speedup=1.010000x\n"
                "Cangjie/HarfBuzz/HarfRust shaping matrix completed: "
                "1 corpora gate_mode=report-only minimum_speedup=1.010000x\n",
                stdout.getvalue(),
            )
            self.assertEqual("", stderr.getvalue())

    def test_run_matrix_preserves_symmetric_endpoint_order(self) -> None:
        args = argparse.Namespace(
            suite="react-dom", cangjie=Path("cangjie"),
            harfbuzz=Path("harfbuzz"), corpus_root=Path("corpus"),
            iterations=2, samples=3, cpu=None, fail_on_slower=False,
            minimum_speedup=matrix.DEFAULT_MINIMUM_SPEEDUP,
        )
        returned = iter(
            self.records((4.0, 8.0, 18.0, 8.0, 2.0, 1.0))
            + self.records((4.0, 8.0, 18.0, 8.0, 2.0, 1.0))
        )
        commands: list[list[str]] = []

        def fake_run(command: list[str], cpu: int | None) -> dict[str, str]:
            del cpu
            commands.append(command)
            return next(returned)

        stdout = io.StringIO()
        with (
            mock.patch.object(matrix, "run", side_effect=fake_run),
            contextlib.redirect_stdout(stdout),
        ):
            outcome = matrix.run_matrix(args, Path("harfrust"))

        self.assertEqual(2, len(outcome.results))
        self.assertEqual(12, len(commands))
        self.assertEqual(
            ["cangjie", "harfbuzz", "harfrust", "harfrust",
             "harfbuzz", "cangjie"],
            [
                "harfrust" if command[0] == "harfrust"
                else command[command.index("--engine") + 1]
                for command in commands[:6]
            ],
        )
        self.assertEqual(
            "roboto-react-dom: cangjie=4.000/1.000 "
            "harfbuzz=8.000/2.000 harfrust=18.000/8.000 "
            "speedup_vs_best=2.000000x minimum_speedup=1.010000x "
            "threshold=met gate_mode=report-only glyphs=10\n"
            "source-serif-react-dom: cangjie=4.000/1.000 "
            "harfbuzz=8.000/2.000 harfrust=18.000/8.000 "
            "speedup_vs_best=2.000000x minimum_speedup=1.010000x "
            "threshold=met gate_mode=report-only glyphs=10\n",
            stdout.getvalue(),
        )


if __name__ == "__main__":
    unittest.main()
