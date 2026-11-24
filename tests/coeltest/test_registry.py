"""Meta tests: the registry matches the files on disk."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import coeltest  # noqa: E402
from coeltest import registry  # noqa: E402


class RegistryTest(unittest.TestCase):
    def test_every_registered_path_exists(self):
        for s in coeltest.discover():
            self.assertTrue(os.path.exists(s.abspath), "%s: %s does not exist" % (s.id, s.abspath))

    def test_ids_are_unique(self):
        ids = [s.id for s in coeltest.discover()]
        self.assertEqual(len(ids), len(set(ids)))

    def test_no_unregistered_test_files(self):
        self.assertEqual(coeltest.unregistered(), [], "add these to tests/coeltest/registry.py (a suite, or SUPPORT for helpers)")

    def test_kinds_are_known(self):
        for s in coeltest.discover():
            self.assertIn(s.kind, ("python", "lua", "node", "shell", "nixos", "manual"), s.id)

    def test_default_selection_skips_slow_and_manual(self):
        ids = {s.id for s in coeltest.select()}
        self.assertNotIn("session-hub", ids)
        self.assertNotIn("hyprland-swipe", ids)
        self.assertIn("hyprland-grid", ids)

    def test_select_by_group_and_glob(self):
        self.assertEqual({s.id for s in coeltest.select(["hyprland"])}, {"hyprland-grid", "hyprland-settings"})
        self.assertIn("gcast-hls", {s.id for s in coeltest.select(["gcast-*"])})

    def test_plan_skips_with_a_reason_when_tools_are_missing(self):
        s = registry.Suite("x", "x", "g", "lua", "hyprland/grid_test.lua", cmds=("definitely-not-installed-xyz",))
        p = coeltest.plan(s, nix="never")
        self.assertIn("missing", p["skip"])

    def test_run_returns_data_for_a_python_suite(self):
        r = coeltest.run_suite(coeltest.get("gcast-discover"))
        self.assertEqual(r["status"], "passed", r)
        self.assertGreater(len(r["tests"]), 0)
        self.assertEqual({"id", "status", "counts", "tests", "duration"} - set(r), set())


if __name__ == "__main__":
    unittest.main()
