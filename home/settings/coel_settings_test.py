"""Tests for coel_settings.py:  python3 home/settings/coel_settings_test.py"""
import os
import subprocess
import sys
import tempfile
import tomllib
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import coel_settings as cs  # noqa: E402

SAMPLE = '''# top comment
[display]
scale = 1.0   # keep me

# monitors below
[monitors.default]
mode = "preferred"

[monitors."desc:A B"]
position = "0x0"

[config.input]
# kb_layout = "us"

[config.input.touchpad]
natural_scroll = true
'''


def edit(fn, text=SAMPLE):
    d = cs.Doc(text)
    fn(d)
    out = d.text()
    tomllib.loads(out)  # must always stay valid TOML
    return out


class DocTests(unittest.TestCase):
    def test_replace_keeps_comment(self):
        out = edit(lambda d: d.set(["display", "scale"], 1.25))
        self.assertIn("scale = 1.25  # keep me", out)
        self.assertEqual(tomllib.loads(out)["display"]["scale"], 1.25)

    def test_other_comments_survive(self):
        out = edit(lambda d: d.set(["display", "scale"], 2))
        self.assertIn("# top comment", out)
        self.assertIn("# monitors below", out)
        self.assertIn('# kb_layout = "us"', out)

    def test_add_key_to_existing_table(self):
        out = edit(lambda d: d.set(["monitors", "default", "scale"], 1.5))
        self.assertEqual(tomllib.loads(out)["monitors"]["default"], {"mode": "preferred", "scale": 1.5})

    def test_add_key_lands_in_right_table(self):
        out = edit(lambda d: d.set(["config", "input", "touchpad", "tap_to_click"], True))
        t = tomllib.loads(out)
        self.assertTrue(t["config"]["input"]["touchpad"]["tap_to_click"])
        self.assertNotIn("tap_to_click", t["config"]["input"])

    def test_new_table_with_quoted_name(self):
        out = edit(lambda d: d.set(["monitors", "desc:X.Y 1", "mode"], "1920x1080@60.000"))
        self.assertEqual(tomllib.loads(out)["monitors"]["desc:X.Y 1"]["mode"], "1920x1080@60.000")

    def test_array_and_string_values(self):
        out = edit(lambda d: d.set(["config", "general", "gaps_out"], [8, 12, 12, 12]))
        self.assertEqual(tomllib.loads(out)["config"]["general"]["gaps_out"], [8, 12, 12, 12])

    def test_unset(self):
        out = edit(lambda d: self.assertTrue(d.unset(["monitors", "default", "mode"])))
        self.assertNotIn("mode", tomllib.loads(out)["monitors"]["default"])

    def test_unset_missing(self):
        self.assertFalse(cs.Doc(SAMPLE).unset(["nope", "x"]))

    def test_root_key(self):
        out = edit(lambda d: d.set(["top"], 1))
        self.assertEqual(tomllib.loads(out)["top"], 1)

    def test_empty_file(self):
        out = edit(lambda d: d.set(["a", "b"], "c"), "")
        self.assertEqual(tomllib.loads(out), {"a": {"b": "c"}})

    def test_replace_value_with_hash_in_string(self):
        out = edit(lambda d: d.set(["a", "k"], "new"), 'a = 1\n[a]\nk = "x # y"  # c\n'.replace("a = 1\n", ""))
        self.assertIn('k = "new"  # c', out)

    def test_split_path(self):
        self.assertEqual(cs.split_path('monitors."desc:A.B C".scale'), ["monitors", "desc:A.B C", "scale"])

    def test_cli_value_inference(self):
        self.assertEqual(cs.parse_cli_value("1.25"), 1.25)
        self.assertEqual(cs.parse_cli_value("true"), True)
        self.assertEqual(cs.parse_cli_value("[1, 2]"), [1, 2])
        self.assertEqual(cs.parse_cli_value("hello"), "hello")
        self.assertEqual(cs.parse_cli_value("1920x1080@60"), "1920x1080@60")


class IdleTests(unittest.TestCase):
    def test_defaults(self):
        secs, w = cs.idle_resolve({})
        self.assertEqual(secs, {"lock": 600, "screen_off": 900, "suspend": 1200})
        self.assertEqual(w, [])

    def test_custom_and_fractional(self):
        secs, _ = cs.idle_resolve({"idle": {"lock_minutes": 2, "screen_off_minutes": 0.5, "suspend_minutes": 0}})
        self.assertEqual(secs, {"lock": 120, "screen_off": 30, "suspend": None})

    def test_false_disables_step(self):
        secs, _ = cs.idle_resolve({"idle": {"suspend_minutes": False}})
        self.assertIsNone(secs["suspend"])

    def test_master_switch(self):
        secs, _ = cs.idle_resolve({"idle": {"enabled": False}})
        self.assertEqual(secs, {"lock": None, "screen_off": None, "suspend": None})

    def test_bad_values_fall_back_to_default_not_to_no_lock(self):
        secs, w = cs.idle_resolve({"idle": {"lock_minutes": "soon", "screen_off_minutes": -5}})
        self.assertEqual(secs["lock"], 600)
        self.assertEqual(secs["screen_off"], 900)
        self.assertEqual(len(w), 2)

    def test_render(self):
        out = cs.render_hypridle({"lock": 120, "screen_off": None, "suspend": 1200}, "LOCK", "SUSP", "ON", "OFF")
        self.assertIn("lock_cmd = LOCK", out)
        self.assertIn("before_sleep_cmd = LOCK", out)
        self.assertIn("after_sleep_cmd = ON", out)
        self.assertEqual(out.count("listener {"), 2)
        self.assertIn("timeout = 120\n    on-timeout = LOCK", out)
        self.assertNotIn("OFF", out)
        self.assertIn("timeout = 1200\n    on-timeout = SUSP", out)


class CliTests(unittest.TestCase):
    def run_cli(self, *args):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "settings.toml")
            open(f, "w").write(SAMPLE)
            env = dict(os.environ, COEL_SETTINGS=f)
            r = subprocess.run([sys.executable, os.path.join(HERE, "coel_settings.py"), *args, "--no-apply"],
                               env=env, capture_output=True, text=True)
            return r, open(f).read()

    def test_set_get_roundtrip(self):
        r, text = self.run_cli("set", "display.scale", "1.5")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(tomllib.loads(text)["display"]["scale"], 1.5)

    def test_unset_missing_fails(self):
        r, _ = self.run_cli("unset", "nope.x")
        self.assertEqual(r.returncode, 1)

    def test_monitor_entry_shapes(self):
        base = {"name": "DP-1", "description": "Dell X 1", "width": 1920, "height": 1080,
                "refreshRate": 60.0, "x": 168, "y": -1080, "scale": 1.0, "transform": 0,
                "disabled": False, "mirrorOf": "none"}
        self.assertEqual(cs.monitor_entry(base), {"mode": "1920x1080@60.000", "scale": 1.0, "position": "168x-1080"})
        self.assertEqual(cs.monitor_entry(dict(base, disabled=True)), {"disabled": True})
        self.assertEqual(cs.monitor_entry(dict(base, transform=1))["transform"], 1)
        self.assertEqual(cs.monitor_key(base), "desc:Dell X 1")
        self.assertEqual(cs.monitor_key(dict(base, description="")), "DP-1")


if __name__ == "__main__":
    unittest.main()
