#!/usr/bin/env python3
"""Parse ~/.ssh/config for LauncherPanel.qml's "ssh" category. Deliberately
a real parser over the actual config file, not a hardcoded list -- same
"real data, not invented" rule list-apps.py follows for .desktop files.

Only literal, connectable Host entries are emitted: a `Host` line naming
more than one alias, or containing a glob character (`*`/`?`), is a
pattern block (e.g. the common `Host *` global-defaults idiom) rather than
a real host, and is skipped entirely -- it has nothing meaningful to show
as "the host" in a launcher row. Directives outside any Host block (this
user's real config has a stray top-level LocalForward line) are ignored,
same reasoning.

HostName defaults to the alias itself and Port to 22 when unset, matching
real ssh(1) behavior -- so what's shown always reflects what `ssh <alias>`
would actually resolve to, not just what's literally written.
"""
import json
import os
import re


def parse_ssh_config(path):
    hosts = []
    current = None
    try:
        with open(path, "r", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return []

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r"\s+", line, maxsplit=1)
        if len(parts) < 2:
            continue
        key, value = parts[0].lower(), parts[1].strip()

        if key == "host":
            aliases = value.split()
            if len(aliases) != 1 or any(c in aliases[0] for c in "*?"):
                current = None  # pattern block -- not a real, single host
                continue
            current = {"name": aliases[0], "hostname": aliases[0], "user": "", "port": 22, "identityFile": ""}
            hosts.append(current)
            continue

        if current is None:
            continue

        if key == "hostname":
            current["hostname"] = value
        elif key == "user":
            current["user"] = value
        elif key == "port":
            try:
                current["port"] = int(value)
            except ValueError:
                pass
        elif key == "identityfile" and not current["identityFile"]:
            current["identityFile"] = value

    return hosts


def main():
    config_path = os.path.expanduser("~/.ssh/config")
    print(json.dumps(parse_ssh_config(config_path)))


if __name__ == "__main__":
    main()
