"""The list of test suites. Add a suite here when you add a test file (the `meta` suite fails if one is missing).

A suite is one test file (or one script) plus what it needs to run:

  kind    python | lua | node | shell | nixos | manual
            python  a unittest module (loaded, never run as a script) -> one result per test
            lua     dofile()d by a driver; the file RETURNS {passed, failed, results}
            node    require()d by a driver; the file EXPORTS {passed, failed, results}
            shell   a script; its exit status is the result (one result)
            nixos   a command (nix build of a NixOS VM test); exit status is the result
            manual  documented here so it is not lost, but never run by the runner
  tags    unit (fast, no environment) | integration (spawns processes / private buses) | slow (minutes, opt-in via --all)
  cmds    executables that must exist; pymods: python modules that must import
  nix     nixpkgs attributes to wrap the run in `nix-shell -p ...` when something in cmds/pymods is missing
"""

import json
import os
import tempfile
from dataclasses import dataclass, field

TESTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(TESTS)


@dataclass
class Suite:
    id: str
    title: str
    group: str
    kind: str
    path: str                                   # relative to tests/ (or to the repo for `repo_path` suites)
    tags: tuple = ("unit",)
    cmds: tuple = ()
    pymods: tuple = ()
    nix: tuple = ()
    args: tuple = ()
    timeout: int = 300
    repo_path: bool = False                     # `path` is relative to the repo root instead of tests/
    note: str = ""                              # shown for manual suites / extra context
    prepare: object = None                      # callable(tmpdir) -> env dict, run before the suite
    command: tuple = ()                         # nixos: the full command, with {repo} / {tests} placeholders

    @property
    def abspath(self):
        return os.path.join(REPO if self.repo_path else TESTS, self.path)

    @property
    def runnable(self):
        return self.kind != "manual"

    @property
    def default(self):
        return self.runnable and "slow" not in self.tags


def _settings_json_env(tmp):
    """hyprland-settings also compares Lua's parse of the real settings.toml with Python's tomllib."""
    import tomllib
    src = os.path.join(REPO, "settings.toml")
    out = os.path.join(tmp, "settings.json")
    with open(src, "rb") as f, open(out, "w") as g:
        json.dump(tomllib.load(f), g)
    return {"COEL_TEST_JSON": out, "COEL_TEST_FILE": src}


DBUS_PY = ("dbus", "python3Packages.dbus-fast")

SUITES = [
    Suite("bluetooth-agent", "Bluetooth pairing agent (BlueZ Agent1, ops, socket protocol)", "bluetooth", "python",
          "bluetooth_agent/test_coel_bt_agent.py", ("integration",), cmds=("dbus-daemon",), pymods=("dbus_fast",), nix=DBUS_PY),

    Suite("gcast-castv2", "Google Cast: CASTV2 protocol client vs mock device", "gcast", "python",
          "gcast/test_castv2.py", ("unit",), cmds=("openssl",), nix=("openssl",)),
    Suite("gcast-discover", "Google Cast: mDNS discovery parsing", "gcast", "python", "gcast/test_discover.py"),
    Suite("gcast-hls", "Google Cast: HLS server", "gcast", "python", "gcast/test_hls.py"),
    Suite("gcast-integration", "Google Cast: engine end to end vs mock device (needs gstreamer + x264/hlssink2/fdkaac)", "gcast",
          "python", "gcast/integration.py", ("integration", "slow"), cmds=("gst-launch-1.0", "openssl")),

    Suite("miracast-wfd", "Miracast: Wi-Fi Display protocol logic", "miracast", "python", "miracast/test_wfd.py"),
    Suite("miracast-profiles", "Miracast: per-sink profiles", "miracast", "python", "miracast/test_profiles.py"),
    Suite("miracast-linkd", "Miracast: link daemon helpers", "miracast", "python", "miracast/test_miracast_linkd.py"),
    Suite("miracast-integration", "Miracast: daemon + CLI vs mock wpa_supplicant on a private bus", "miracast", "shell",
          "miracast/run-integration.sh", ("integration",), cmds=("dbus-daemon", "python3"), pymods=("dbus_fast",), nix=DBUS_PY),
    Suite("miracast-portal", "Miracast: portal_capture vs mock portal (session, fd passing, cancel)", "miracast", "shell",
          "miracast/run-portal-test.sh", ("integration",), cmds=("dbus-daemon", "python3"), pymods=("dbus_fast",), nix=DBUS_PY),
    Suite("miracast-engine-e2e", "Miracast: source engine vs mock sink (negotiation only)", "miracast", "shell",
          "miracast/engine_e2e.sh", ("integration",), cmds=("python3",)),

    Suite("settings", "coel-settings: settings.toml read/write/sync", "settings", "python", "settings/test_coel_settings.py"),

    Suite("hyprland-grid", "Hyprland: workspace grid logic (Lua 5.5, fake host)", "hyprland", "lua", "hyprland/grid_test.lua",
          cmds=("lua",), nix=("lua5_5",)),
    Suite("hyprland-settings", "Hyprland: settings.lua TOML parser (+ real settings.toml vs tomllib)", "hyprland", "lua",
          "hyprland/settings_test.lua", cmds=("lua",), nix=("lua5_5",), prepare=_settings_json_env),

    Suite("overview-layout", "Quickshell: workspace overview layout logic (Node)", "quickshell", "node", "quickshell/layout.test.js",
          cmds=("node",), nix=("nodejs",)),

    Suite("session-hub", "Session hub / VT guard / greetd (NixOS VM test, minutes)", "nixos", "nixos", "nixos/session-hub-test.nix",
          ("slow",), cmds=("nix",), timeout=1800,
          command=("nix", "build", "--impure", "--no-link", "--print-out-paths", "--expr",
                   'let f = builtins.getFlake "path:{repo}"; pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; }; '
                   'in pkgs.testers.runNixOSTest {tests}/nixos/session-hub-test.nix')),

    Suite("meta", "Test runner: every test file is registered, every registered path exists", "meta", "python",
          "coeltest/test_registry.py"),

    Suite("hyprland-swipe", "Hyprland grid-swipe patch (synthetic trackpad swipes in a nested Hyprland)", "hyprland", "manual",
          "hyprland-swipe", ("manual",),
          note="Build tests/hyprland-swipe/plugin.nix against the patched Hyprland and load it into a throwaway nested Hyprland; see TODO.md."),
    Suite("theme-visual", "Theme check: palette, notifications, rofi, borders, hyprlock (look at it)", "theme", "manual",
          "home/theme/theme-test.sh", ("manual",), repo_path=True, note="Interactive and visual: run `coel-theme-test`."),
]

# Files in tests/ that are fixtures / helpers, not suites.
SUPPORT = {
    "gcast/mock_cast.py", "miracast/mock_portal.py", "miracast/mock_sink.py", "miracast/mock_wpa.py", "miracast/portal_e2e.py",
    "miracast/integration.sh", "hyprland-swipe/plugin.nix", "hyprland-swipe/swipetest.cpp",
}
