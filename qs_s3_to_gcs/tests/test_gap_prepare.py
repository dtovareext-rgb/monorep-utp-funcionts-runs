"""Tests de gap_prepare (sin S3/BQ reales)."""

from __future__ import annotations

import os
import unittest
from datetime import date
from unittest.mock import patch

from gap_utils import GAP_SYNC_MODE, resolve_gap_target_date


class ResolveGapTargetDateTests(unittest.TestCase):
    def test_from_env(self) -> None:
        with patch.dict(os.environ, {"GAP_TARGET_DATE": "2026-09-07"}, clear=False):
            self.assertEqual(resolve_gap_target_date({}), date(2026, 9, 7))

    def test_from_config(self) -> None:
        self.assertEqual(
            resolve_gap_target_date({"gap": {"target_date": "2026-08-15"}}),
            date(2026, 8, 15),
        )

    def test_missing_raises(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                resolve_gap_target_date({})


class GapSyncModeTests(unittest.TestCase):
    def test_constant(self) -> None:
        self.assertEqual(GAP_SYNC_MODE, "gap_fill")


if __name__ == "__main__":
    unittest.main()
