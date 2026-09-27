#!/usr/bin/env python3
"""Fetch/cache the real, always-current emoji dataset for LauncherPanel.qml's
emoji search, straight from Unicode.org's own canonical emoji-test.txt --
the file the Unicode Consortium itself keeps updated as new emoji versions
are approved (Emoji 18.0 as of this writing) -- rather than the one-time
vendored snapshot this launcher used to rely on exclusively, which was
copied from pkgs.rofi-emoji 4.1.0 and had gone two full Unicode Emoji
versions stale by the time anyone noticed (missing everything from 17.0
and 18.0: shaking face, cracking face, pickle, lighthouse, meteor, ...).

Cached at $XDG_CACHE_HOME/quickshell-emoji-data.txt, re-fetched at most
once every REFRESH_DAYS -- frequent enough that new emoji show up within
about a week of Unicode publishing them, infrequent enough not to hit
unicode.org on every single launcher open. A failed/timed-out fetch (no
network, unicode.org unreachable, etc.) silently keeps whatever's already
cached, or falls back to the vendored emoji-data.txt bundled in this repo
if there's no cache yet at all -- the launcher should never hang or come
up with zero emoji just because the network's unavailable.

emoji-test.txt has no search keywords of its own, only the official CLDR
short name grouped by category/subgroup -- keywords are enriched here
from the vendored file by exact emoji-character lookup, so existing
fuzzy search (e.g. "surprised" -> shaking face) doesn't regress. A
brand-new emoji not yet in that snapshot just matches on its name alone
until enriched some other way -- graceful degradation, not a hard
dependency on keywords existing.
"""
import os
import re
import sys
import time
import urllib.request

EMOJI_TEST_URL = "https://www.unicode.org/Public/emoji/latest/emoji-test.txt"
REFRESH_DAYS = 7
FETCH_TIMEOUT = 5

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENDORED_PATH = os.path.join(SCRIPT_DIR, "emoji-data.txt")

LINE_RE = re.compile(r"^[0-9A-Fa-f ]+;\s*(\S+)\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$")


def cache_path():
    cache_home = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    return os.path.join(cache_home, "quickshell-emoji-data.txt")


def load_tsv(path):
    rows = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line:
                    continue
                parts = line.split("\t")
                if len(parts) < 4:
                    continue
                rows.append(parts)
    except OSError:
        pass
    return rows


def keyword_lookup():
    lut = {}
    for parts in load_tsv(VENDORED_PATH):
        char = parts[0]
        keywords = parts[4] if len(parts) > 4 else ""
        lut[char] = keywords
    return lut


def parse_emoji_test(text, keywords_lut):
    group = ""
    subgroup = ""
    out = []
    for line in text.splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if line.startswith("# subgroup:"):
            subgroup = line.split(":", 1)[1].strip()
            continue
        if not line or line.startswith("#"):
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        status, char, name = m.groups()
        if status != "fully-qualified":
            continue
        out.append((char, group, subgroup, name, keywords_lut.get(char, "")))
    return out


def write_tsv(path, rows):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for row in rows:
            f.write("\t".join(row) + "\n")
    os.replace(tmp, path)


def print_tsv(rows):
    for row in rows:
        sys.stdout.write("\t".join(row) + "\n")


def main():
    cache = cache_path()
    needs_fetch = True
    if os.path.exists(cache):
        age_days = (time.time() - os.path.getmtime(cache)) / 86400
        needs_fetch = age_days > REFRESH_DAYS

    if needs_fetch:
        try:
            req = urllib.request.Request(EMOJI_TEST_URL, headers={"User-Agent": "coelos-quickshell-launcher"})
            with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as resp:
                text = resp.read().decode("utf-8", errors="replace")
            rows = parse_emoji_test(text, keyword_lookup())
            if rows:
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                write_tsv(cache, rows)
        except Exception:
            pass

    if os.path.exists(cache):
        print_tsv(load_tsv(cache))
    else:
        print_tsv(load_tsv(VENDORED_PATH))


if __name__ == "__main__":
    main()
