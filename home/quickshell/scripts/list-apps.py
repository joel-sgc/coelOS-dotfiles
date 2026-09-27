#!/usr/bin/env python3
"""Enumerate installed .desktop launchers as JSON, for LauncherPanel.qml's
app search (the rofi `-show drun` replacement). Deliberately not a rofi/
xdg-desktop-menu wrapper -- this parses the entries directly so the
launcher can search/rank them itself, same as its other categories.

Walks $XDG_DATA_HOME/applications then each $XDG_DATA_DIRS entry's
applications dir, in that order -- standard XDG precedence, so a
user-local override of a system .desktop file (same basename) wins.
NoDisplay/Hidden entries and non-Application types are dropped, matching
what a normal app menu would show.
"""
import glob
import json
import os
import re
import shlex


def app_dirs():
    dirs = [os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "applications")]
    for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(os.path.join(d, "applications"))
    return dirs


def parse_desktop(path):
    try:
        with open(path, "r", errors="replace") as f:
            text = f.read()
    except OSError:
        return None

    # Only the [Desktop Entry] section -- stop at the next [section].
    m = re.search(r"^\[Desktop Entry\]\s*$(.*?)(^\[|\Z)", text, re.M | re.S)
    if not m:
        return None
    fields = {}
    for line in m.group(1).split("\n"):
        km = re.match(r"^([A-Za-z0-9_-]+)\s*=\s*(.*)$", line)
        if km:
            fields.setdefault(km.group(1), km.group(2))

    if fields.get("Type", "Application") != "Application":
        return None
    if fields.get("NoDisplay", "false").lower() == "true":
        return None
    if fields.get("Hidden", "false").lower() == "true":
        return None

    name = fields.get("Name")
    exec_raw = fields.get("Exec")
    if not name or not exec_raw:
        return None

    # Field codes (%f/%F/%u/%U/%i/%c/%k/%v/%m/%d/%D/%n/%N) -- meaningless
    # without a real file/URL argument to substitute, so just drop them.
    exec_clean = re.sub(r"%[fFuUickvmdDnN]", "", exec_raw).strip()
    try:
        argv = shlex.split(exec_clean)
    except ValueError:
        argv = exec_clean.split()
    if not argv:
        return None

    return {
        "name": name,
        "comment": fields.get("Comment") or fields.get("GenericName") or "",
        "icon": fields.get("Icon", ""),
        "terminal": fields.get("Terminal", "false").lower() == "true",
        "argv": argv,
    }


def main():
    seen = {}
    for d in app_dirs():
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            base = os.path.basename(path)
            if base in seen:
                continue
            entry = parse_desktop(path)
            if entry:
                seen[base] = entry
    print(json.dumps(list(seen.values())))


if __name__ == "__main__":
    main()
