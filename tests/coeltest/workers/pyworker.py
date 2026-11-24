"""Loads one unittest module and prints its results as JSON (never runs it as a script).

    python3 pyworker.py <path/to/test_file.py>

The last stdout line is  @@COELTEST@@{json}  so anything the tests print cannot be mistaken for the result.
"""

import importlib.util
import json
import os
import sys
import time
import unittest

MARK = "@@COELTEST@@"


class Collector(unittest.TestResult):
    def __init__(self):
        super().__init__()
        self.rows = []
        self._t0 = {}

    @staticmethod
    def name(test):
        tid = test.id()
        parts = tid.split(".")
        return ".".join(parts[-2:]) if len(parts) >= 2 else tid

    def startTest(self, test):
        super().startTest(test)
        self._t0[id(test)] = time.time()

    def _row(self, test, status, message=""):
        self.rows.append({"name": self.name(test), "status": status, "message": message,
                          "duration": round(time.time() - self._t0.get(id(test), time.time()), 4)})

    def addSuccess(self, test):
        super().addSuccess(test)
        self._row(test, "passed")

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self._row(test, "failed", self._exc_info_to_string(err, test))

    def addError(self, test, err):
        super().addError(test, err)
        self._row(test, "error", self._exc_info_to_string(err, test))

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self._row(test, "skipped", reason)

    def addExpectedFailure(self, test, err):
        super().addExpectedFailure(test, err)
        self._row(test, "passed", "expected failure")

    def addUnexpectedSuccess(self, test):
        super().addUnexpectedSuccess(test)
        self._row(test, "failed", "unexpected success")

    def addSubTest(self, test, subtest, err):
        super().addSubTest(test, subtest, err)
        if err is not None:
            self.rows.append({"name": self.name(test) + " " + str(subtest._subDescription()), "status": "failed",
                              "message": self._exc_info_to_string(err, test), "duration": 0})


def run_file(path):
    """Run every test in the module at `path`; returns {"tests": [...]} (no printing, no exit)."""
    path = os.path.abspath(path)
    sys.path.insert(0, os.path.dirname(path))
    name = "coeltest_" + os.path.splitext(os.path.basename(path))[0]
    try:
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[name] = mod
        spec.loader.exec_module(mod)
    except Exception as e:           # import errors (missing module...) are a result, not a crash
        import traceback
        return {"tests": [{"name": "import", "status": "error", "message": traceback.format_exc(), "duration": 0}]}
    result = Collector()
    unittest.defaultTestLoader.loadTestsFromModule(mod).run(result)
    return {"tests": result.rows}


if __name__ == "__main__":
    data = run_file(sys.argv[1])
    sys.stdout.flush()
    print(MARK + json.dumps(data))
