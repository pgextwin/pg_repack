#!/usr/bin/env python3
"""Fail-closed, fixed-name Windows required CI result for maintained-PG matrix.

Never publishes or dispatches. Relies only on GitHub Actions 'needs.windows.result'
for the COMPLETE reusable Windows matrix (not on volatile per-PG job names).
"""
from __future__ import annotations
import os
import sys


def verified_matrix_result(value):
    return type(value) is str and value == "success"


def main():
    if not verified_matrix_result(os.environ.get("WINDOWS_MATRIX_RESULT")):
        print("WINDOWS REQUIRED SUMMARY DENIED: full maintained-PG Windows matrix "
              "was not successful", file=sys.stderr)
        return 2
    print("WINDOWS REQUIRED SUMMARY VERIFIED: full maintained-PG Windows matrix "
          "completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
