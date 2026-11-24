# Tests

Every test in the repo lives here, grouped by what it tests. One runner runs any of them from a CLI or a terminal UI, and
every test can also be loaded from Python **as data** (nothing prints or exits).

```
python3 tests/run.py                       # every fast suite (unit + integration; not slow, not manual)
python3 tests/run.py gcast hyprland-grid   # by suite id, group name or glob (miracast-*)
python3 tests/run.py --tui                 # pick suites in a terminal UI
python3 tests/run.py --list                # what exists and whether it can run here
python3 tests/run.py --all                 # also the slow ones (NixOS VM test, gstreamer integration)
python3 tests/run.py --json                # the full report as JSON
python3 tests/run.py --check               # is every test file registered?
```

Options: `-t unit|integration|slow` filter by tag, `-x PATTERN` exclude, `-j N` parallel suites (default 4), `-v` list
every test, `--nix auto|always|never` (see below). Exit status is 0 only when no suite failed.

The terminal UI: space toggles a suite, `a` all, `d` defaults, `n` none, `g` a whole group, `/` filters, enter runs, then
enter on a result shows its tests, failure messages and output, `r` reruns the failures, `b` goes back to the list.

## Layout

| directory | tests | needs |
|---|---|---|
| `bluetooth_agent/` | the BlueZ pairing agent (`home/bluetooth-agent`) against a fake bluetoothd on a private bus | dbus-daemon, dbus-fast |
| `gcast/` | Google Cast protocol client, discovery, HLS server (+ `mock_cast.py`, the end-to-end `integration.py`) | openssl; gstreamer for the integration |
| `miracast/` | Wi-Fi Display logic, profiles, link-daemon helpers; shell end-to-end runs against mock wpa_supplicant / sink / portal | dbus-daemon, dbus-fast for the daemon and portal runs |
| `settings/` | `coel-settings` and `settings.toml` | python (tomllib) |
| `hyprland/` | workspace grid logic and the settings.lua TOML parser, under Lua 5.5 | lua |
| `quickshell/` | the overview's layout logic, under Node | node |
| `nixos/` | the session hub / VT guard as a NixOS VM test (slow) | nix |
| `hyprland-swipe/` | synthetic trackpad swipes for a nested Hyprland | — |
| `coeltest/` | the runner itself, plus its own `meta` suite | — |

`home/theme/theme-test.sh` (`coel-theme-test`) is a visual check you run by eye; it stays where its package expects it and is
listed here as the manual suite `theme-visual`.

**Missing tools.** If a suite needs something that is not installed (lua, node, dbus-daemon, dbus-fast...), the default
`--nix auto` runs it inside `nix-shell -p <packages>`. `--nix never` skips such suites with the reason instead; `--nix always`
wraps every suite that declares packages.

## From Python

```python
import sys; sys.path.insert(0, "tests")
import coeltest

suites = coeltest.select(["gcast", "hyprland-grid"])     # ids, group names or globs; no arguments = the default set
report = coeltest.run(suites, jobs=4)                    # blocks, prints nothing
report["summary"]    # {"suites": 5, "suites_passed": 5, ..., "passed": 119, "failed": 0, "ok": True}
report["suites"][0]  # {"id", "status", "counts", "tests": [{"name", "status", "message", "duration"}], "output", ...}
coeltest.run_suite(coeltest.get("gcast-hls"))            # one suite
```

How each kind of test returns data (this is what "not a CLI" means here):

* **python**: a normal `unittest` module. The runner loads it, never executes it as a script, and collects one result per test.
* **lua**: `dofile()` the file and it **returns** `{passed, failed, results = {{name, ok, error}, ...}}`. Run as a script
  (`lua tests/hyprland/grid_test.lua`) it prints a summary and sets the exit status instead.
* **node**: `require()` the file and it **exports** `{passed, failed, results}`; run as a script it prints and exits.
* **shell / nixos**: scripts are CLIs by nature, so the runner reports their exit status and output as one result.

## Adding a test

1. Put the file in the matching directory (new component: new directory) and make sure it finds the code under test from
   its own location (`os.path.dirname(__file__)` + `..`, `..`, `modules/...`), not from the current directory.
2. Add a `Suite(...)` to `coeltest/registry.py`: kind, tags, what it needs (`cmds`, `pymods`) and which nixpkgs attributes
   provide them (`nix`). Fixtures/helpers go in `SUPPORT`.
3. `python3 tests/run.py --check` (and the `meta` suite) fail until every test-looking file is registered.
4. For a flake check, add a line to `checks` in `flake.nix` (`name = suite "<id>" [ tools ];`).

`nix flake check` runs the pure suites in the sandbox (hyprland-grid, hyprland-settings, overview-layout, settings, gcast-castv2/
discover/hls, miracast-wfd/profiles/linkd, test-runner); the ones that need a private D-Bus, gstreamer or a VM run through the runner.
