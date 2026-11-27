#!/usr/bin/env python3
"""Print one table of settings.toml as JSON (QML can't read TOML).

    settings-table.py modes      -> {"class": {...}, ...}

A missing or broken file prints {} so callers fall back to their defaults.
"""
import json
import os
import sys
import tomllib

path = os.path.expanduser(os.environ.get("COEL_SETTINGS", "~/.nixos/settings.toml"))
try:
    with open(path, "rb") as f:
        data = tomllib.load(f)
except (OSError, tomllib.TOMLDecodeError) as e:
    print("settings-table: %s" % e, file=sys.stderr)
    data = {}
for key in (sys.argv[1].split(".") if len(sys.argv) > 1 else []):
    data = data.get(key, {}) if isinstance(data, dict) else {}
print(json.dumps(data))
