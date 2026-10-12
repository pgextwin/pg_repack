#!/usr/bin/env python3
"""Test the exact stable aggregate check used by Windows CI, without Release."""
import importlib.util
from pathlib import Path
import os
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "summary", ROOT / "scripts" / "required_windows_summary.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WindowsSummaryTests(unittest.TestCase):
    def test_success_only(self):
        self.assertTrue(module.verified_matrix_result("success"))
        for value in ("failure", "cancelled", "skipped", "", "Success",
                      "success ", True, 1, None):
            with self.subTest(value=value):
                self.assertFalse(module.verified_matrix_result(value))

    def test_real_exit_status_allow_and_deny(self):
        path = ROOT / "scripts" / "required_windows_summary.py"
        for value, expected in (("success", 0), ("failure", 2),
                                ("cancelled", 2), ("skipped", 2), ("", 2)):
            env = dict(os.environ, WINDOWS_MATRIX_RESULT=value)
            res = subprocess.run([sys.executable, str(path)], env=env,
                                 capture_output=True, text=True)
            with self.subTest(result=value):
                self.assertEqual(res.returncode, expected)

    def test_workflow_depends_on_complete_reusable_matrix_not_pg14_name(self):
        contents = (ROOT / ".github" / "workflows" / "windows.yml").read_text()
        self.assertIn("  windows_required:", contents)
        summary = contents.split("  windows_required:", 1)[1].split(
            "\n  candidate_report:", 1)[0]
        self.assertIn("name: Windows required summary", summary)
        self.assertIn("needs: windows", summary)
        self.assertIn("always()", summary)
        self.assertIn("needs.windows.result", summary)
        self.assertIn("scripts/required_windows_summary.py", summary)
        self.assertNotIn("PostgreSQL 14", summary)
        self.assertNotIn("workflow_dispatch:", summary)


if __name__ == "__main__":
    unittest.main()
