"""Boundary tests for the non-shaping cross-library performance gates."""

from __future__ import annotations

import math
import unittest

from tools import run_fontations_matrix as fontations
from tools import run_freetype_matrix as freetype
from tools import run_hinted_outline_matrix as hinted


class PerformanceMatrixThresholdTest(unittest.TestCase):
    def test_default_thresholds_require_one_percent_margin(self) -> None:
        self.assertEqual(1.01, fontations.DEFAULT_MINIMUM_SPEEDUP)
        self.assertEqual(1.01, freetype.DEFAULT_MINIMUM_SPEEDUP)
        self.assertEqual(1.01, hinted.DEFAULT_MINIMUM_SPEEDUP)

    def test_threshold_boundary_is_inclusive(self) -> None:
        for module in (fontations, freetype):
            minimum = module.DEFAULT_MINIMUM_SPEEDUP
            self.assertTrue(module.meets_speedup_gate(minimum, minimum))
            self.assertFalse(
                module.meets_speedup_gate(
                    math.nextafter(minimum, -math.inf), minimum
                )
            )
            self.assertFalse(module.meets_speedup_gate(math.nan, minimum))
        minimum = hinted.DEFAULT_MINIMUM_SPEEDUP
        self.assertTrue(hinted.passes_gate(minimum))
        self.assertFalse(hinted.passes_gate(math.nextafter(minimum, -math.inf)))
        self.assertFalse(hinted.passes_gate(math.nan))

    def test_threshold_configuration_rejects_parity_and_non_finite_values(self) -> None:
        for module in (fontations, freetype, hinted):
            self.assertFalse(module.valid_minimum_speedup(1.0))
            self.assertFalse(module.valid_minimum_speedup(math.inf))
            self.assertFalse(module.valid_minimum_speedup(math.nan))
            self.assertTrue(module.valid_minimum_speedup(1.01))

    def test_fontations_row_manifest_matches_current_runner(self) -> None:
        self.assertEqual(28, len(fontations.CASES))
        self.assertEqual(8, fontations.expected_row_count(
            source="varc", extended=False
        ))
        self.assertEqual(33, fontations.expected_row_count(
            source="all", extended=False
        ))
        self.assertEqual(133, fontations.expected_row_count(
            source="all", extended=True
        ))


if __name__ == "__main__":
    unittest.main()
