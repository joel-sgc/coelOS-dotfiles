#!/usr/bin/env python3
"""Run the repo's tests.   python3 tests/run.py --help

  python3 tests/run.py                  every fast suite
  python3 tests/run.py gcast hyprland-grid
  python3 tests/run.py --tui            pick suites in a terminal UI
  python3 tests/run.py --list
  python3 tests/run.py --json           machine-readable report

From Python:  import coeltest; coeltest.run(coeltest.select(["gcast"]))   (returns data, prints nothing)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from coeltest.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
