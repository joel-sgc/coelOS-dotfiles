"""coeltest: discover and run this repo's tests, returning data.

    import coeltest
    suites = coeltest.select(["gcast", "hyprland-grid"])     # ids, group names or globs
    report = coeltest.run(suites, jobs=4)                    # {"suites": [...], "summary": {...}, "duration": s}

The command line (`python3 tests/run.py`) and the terminal UI (`python3 tests/run.py --tui`) are thin layers on top of this.
"""

from .registry import REPO, SUITES, TESTS, Suite
from .runner import (NIX_MODES, discover, get, missing_requirements, plan, run, run_suite, select, summarize,
                     unregistered)

__all__ = ["REPO", "SUITES", "TESTS", "Suite", "NIX_MODES", "discover", "get", "missing_requirements", "plan", "run",
           "run_suite", "select", "summarize", "unregistered"]
