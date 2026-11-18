#!/usr/bin/env python3
"""coel-settings: read and edit settings.toml (the runtime settings file).

  coel-settings get  <path>            table.key, or a whole table
  coel-settings set  <path> <value>    value is TOML (1.25, true, "x", [1,2]); bare text = string
  coel-settings unset <path>
  coel-settings list                   print the file
  coel-settings edit                   open in $EDITOR, then apply
  coel-settings apply                  make Hyprland re-read the file (hyprctl reload)
  coel-settings sync-monitors          save the *live* monitor layout into [monitors.*]
  coel-settings render-hypridle ...    print/write hypridle's config from [idle] (used by the service)
  coel-settings validate
  coel-settings path

`set`/`unset`/`sync-monitors` apply afterwards unless --no-apply. Edits are
line-based, so comments and layout in the file survive. Paths are dotted and
quote-aware: monitors."desc:BOE 0x0BCA".scale

File: $COEL_SETTINGS, else ~/.nixos/settings.toml
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib

MONITOR_KEYS = ("mode", "position", "scale", "transform", "mirror", "disabled")


def settings_path():
    return os.path.expanduser(os.environ.get("COEL_SETTINGS", "~/.nixos/settings.toml"))


# ------------------------------------------------------------------ paths
def split_path(p):
    """a.b."c.d" -> ['a','b','c.d']"""
    parts, i = [], 0
    while i < len(p):
        c = p[i]
        if c == ".":
            i += 1
        elif c in "\"'":
            j = p.find(c, i + 1)
            if j < 0:
                raise ValueError("unterminated quote in path")
            parts.append(p[i + 1:j])
            i = j + 1
        else:
            m = re.match(r"[A-Za-z0-9_\-]+", p[i:])
            if not m:
                raise ValueError(f"bad path {p!r}")
            parts.append(m.group(0))
            i += len(m.group(0))
    return parts


def fmt_key(k):
    return k if re.fullmatch(r"[A-Za-z0-9_\-]+", k) else json.dumps(k)


def fmt_header(parts):
    return "[" + ".".join(fmt_key(k) for k in parts) + "]"


def fmt_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ", ".join(fmt_value(x) for x in v) + "]"
    raise TypeError(f"cannot write {type(v).__name__}")


def parse_cli_value(s):
    try:
        return tomllib.loads("v = " + s)["v"]
    except tomllib.TOMLDecodeError:
        return s


# ------------------------------------------------------------------ document
HEADER_RE = re.compile(r"^\s*\[(?!\[)(.*?)\]\s*(#.*)?$")
KEY_RE = re.compile(r'^(\s*)("(?:[^"\\]|\\.)*"|[A-Za-z0-9_\-]+)\s*=\s*(.*)$')


def value_end(rest):
    """Index where the value in `rest` ends (so a trailing comment can be kept)."""
    i, depth, q = 0, 0, None
    while i < len(rest):
        c = rest[i]
        if q:
            if c == "\\" and q == '"':
                i += 1
            elif c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
        elif c == "#" and depth == 0:
            break
        i += 1
    return len(rest[:i].rstrip())


class Doc:
    def __init__(self, text):
        self.lines = text.split("\n")
        if self.lines and self.lines[-1] == "":
            self.lines.pop()

    def text(self):
        return "\n".join(self.lines) + "\n"

    def _tables(self):
        """[(parts, start, end)] with start = header line, end = one past last line."""
        heads = []
        for n, l in enumerate(self.lines):
            m = HEADER_RE.match(l)
            if m:
                try:
                    heads.append((split_path(m.group(1)), n))
                except ValueError:
                    pass
        out = []
        for idx, (parts, n) in enumerate(heads):
            end = heads[idx + 1][1] if idx + 1 < len(heads) else len(self.lines)
            out.append((parts, n, end))
        return out

    def _root_end(self):
        t = self._tables()
        return t[0][1] if t else len(self.lines)

    def find_table(self, parts):
        for p, s, e in self._tables():
            if p == parts:
                return s, e
        return None

    def _find_key(self, start, end, key):
        for n in range(start, end):
            m = KEY_RE.match(self.lines[n])
            if m:
                k = m.group(2)
                k = json.loads(k) if k.startswith('"') else k
                if k == key:
                    return n
        return None

    def set(self, parts, value):
        *tbl, key = parts
        newval = fmt_value(value)
        if not tbl:
            lo, hi = 0, self._root_end()
            at_root = True
        else:
            span = self.find_table(tbl)
            if span is None:
                while self.lines and self.lines[-1].strip() == "":
                    self.lines.pop()
                if self.lines:
                    self.lines.append("")
                self.lines += [fmt_header(tbl), f"{fmt_key(key)} = {newval}"]
                return
            lo, hi = span[0] + 1, span[1]
            at_root = False
        n = self._find_key(lo, hi, key)
        if n is not None:
            m = KEY_RE.match(self.lines[n])
            rest = m.group(3)
            comment = rest[value_end(rest):]
            self.lines[n] = f"{m.group(1)}{m.group(2)} = {newval}" + (("  " + comment.strip()) if comment.strip() else "")
            return
        # insert after the table's last key line (before trailing blanks/comments)
        last = lo - 1 if not at_root else -1
        for i in range(lo, hi):
            if KEY_RE.match(self.lines[i]):
                last = i
        self.lines.insert(last + 1, f"{fmt_key(key)} = {newval}")

    def unset(self, parts):
        *tbl, key = parts
        span = (0, self._root_end()) if not tbl else self.find_table(tbl)
        if span is None:
            return False
        lo, hi = (span[0], span[1]) if not tbl else (span[0] + 1, span[1])
        n = self._find_key(lo, hi, key)
        if n is None:
            return False
        del self.lines[n]
        return True


# ------------------------------------------------------------------ file io
def read_text():
    try:
        with open(settings_path()) as f:
            return f.read()
    except FileNotFoundError:
        return ""


def write_text(text):
    tomllib.loads(text)  # refuse to write a file that no longer parses
    path = settings_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    if os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)


def apply():
    r = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True)
    if r.returncode != 0:
        print("coel-settings: hyprctl reload failed: " + (r.stderr or r.stdout).strip(), file=sys.stderr)
    apply_idle()
    return r.returncode


def apply_idle():
    """hypridle only reads its config at start, so restart it -- but only when the
    [idle] values changed (a restart resets the idle timers)."""
    try:
        data = tomllib.loads(read_text())
    except tomllib.TOMLDecodeError:
        return
    now, _ = idle_resolve(data)
    try:
        with open(IDLE_APPLIED) as f:
            if json.load(f) == now:
                return
    except (OSError, ValueError):
        pass
    active = subprocess.run(["systemctl", "--user", "is-active", "--quiet", "hypridle"]).returncode == 0
    if active:
        subprocess.run(["systemctl", "--user", "restart", "hypridle"])


# ------------------------------------------------------------------ idle
IDLE_APPLIED = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "coel-idle-applied.json")
IDLE_DEFAULTS = {"lock_minutes": 10, "screen_off_minutes": 15, "suspend_minutes": 20}


def idle_resolve(data):
    """[idle] -> ({lock, screen_off, suspend: seconds or None=disabled}, [warnings]).

    A value of 0 (or false) disables that step; bad values fall back to the
    default with a warning, so a typo never leaves the machine without a lock."""
    idle = data.get("idle", {}) if isinstance(data.get("idle"), dict) else {}
    warns, out = [], {}
    enabled = idle.get("enabled", True)
    if not isinstance(enabled, bool):
        warns.append("idle.enabled must be true/false; using true")
        enabled = True
    for name in ("lock", "screen_off", "suspend"):
        key = f"{name}_minutes"
        v = idle.get(key, IDLE_DEFAULTS[key])
        if v is False:
            v = 0
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0:
            warns.append(f"idle.{key} must be a number of minutes >= 0; using {IDLE_DEFAULTS[key]}")
            v = IDLE_DEFAULTS[key]
        out[name] = round(v * 60) if enabled and v > 0 else None
    return out, warns


def render_hypridle(secs, lock_cmd, suspend_cmd, dpms_on, dpms_off):
    lines = [
        "general {",
        f"    lock_cmd = {lock_cmd}",
        f"    before_sleep_cmd = {lock_cmd}",
        f"    after_sleep_cmd = {dpms_on}",
        "}",
    ]
    steps = [
        ("lock", {"on-timeout": lock_cmd}),
        ("screen_off", {"on-timeout": dpms_off, "on-resume": dpms_on}),
        ("suspend", {"on-timeout": suspend_cmd}),
    ]
    for name, cmds in steps:
        if secs[name] is None:
            continue
        lines += ["", "listener {", f"    timeout = {secs[name]}"]
        lines += [f"    {k} = {v}" for k, v in cmds.items()]
        lines.append("}")
    return "\n".join(lines) + "\n"


def cmd_render_hypridle(rest):
    opts, i = {}, 0
    while i < len(rest):
        if not rest[i].startswith("--") or i + 1 >= len(rest):
            return usage()
        opts[rest[i][2:]] = rest[i + 1]
        i += 2
    need = ("lock-cmd", "suspend-cmd", "dpms-on-cmd", "dpms-off-cmd")
    if any(k not in opts for k in need):
        print("render-hypridle needs " + " ".join("--" + k for k in need) + " [--out FILE]", file=sys.stderr)
        return 2
    try:
        data = tomllib.loads(read_text())
    except tomllib.TOMLDecodeError as e:
        print(f"coel-settings: settings.toml invalid ({e}); using idle defaults", file=sys.stderr)
        data = {}
    secs, warns = idle_resolve(data)
    for w in warns:
        print("coel-settings: " + w, file=sys.stderr)
    text = render_hypridle(secs, opts["lock-cmd"], opts["suspend-cmd"], opts["dpms-on-cmd"], opts["dpms-off-cmd"])
    if "out" in opts:
        with open(opts["out"], "w") as f:
            f.write(text)
        try:
            with open(IDLE_APPLIED, "w") as f:
                json.dump(secs, f)
        except OSError:
            pass
    else:
        sys.stdout.write(text)
    return 0


# ------------------------------------------------------------------ monitors
def live_monitors():
    out = subprocess.run(["hyprctl", "monitors", "all", "-j"], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def monitor_entry(m):
    """Settings values for one monitor, as Hyprland currently has it."""
    if m.get("disabled"):
        return {"disabled": True}
    e = {
        "mode": f"{m['width']}x{m['height']}@{m['refreshRate']:.3f}",
        "scale": round(float(m["scale"]), 4),
    }
    mirror = m.get("mirrorOf")
    if mirror not in (None, "none", -1, "-1"):
        e["mirror"] = next((x["name"] for x in live_monitors() if x.get("id") == mirror or x.get("name") == mirror), str(mirror))
        e["position"] = "auto"
    else:
        e["position"] = f"{m['x']}x{m['y']}"
    if m.get("transform"):
        e["transform"] = m["transform"]
    return e


def monitor_key(m):
    d = (m.get("description") or "").strip()
    return f"desc:{d}" if d else m["name"]


def sync_monitors(doc):
    for m in live_monitors():
        tbl = ["monitors", monitor_key(m)]
        entry = monitor_entry(m)
        for k in MONITOR_KEYS:
            if k in entry:
                doc.set(tbl + [k], entry[k])
            else:
                doc.unset(tbl + [k])


# ------------------------------------------------------------------ commands
def lookup(data, parts):
    for k in parts:
        data = data[k]
    return data


def show(v, prefix=""):
    if isinstance(v, dict):
        for k, x in v.items():
            if isinstance(x, dict):
                show(x, prefix + fmt_key(k) + ".")
            else:
                print(f"{prefix}{fmt_key(k)} = {fmt_value(x)}")
    else:
        print(fmt_value(v))


def main(argv):
    args = [a for a in argv if a != "--no-apply"]
    do_apply = "--no-apply" not in argv
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, rest = args[0], args[1:]

    if cmd == "path":
        print(settings_path())
    elif cmd == "list":
        sys.stdout.write(read_text())
    elif cmd == "validate":
        try:
            tomllib.loads(read_text())
        except tomllib.TOMLDecodeError as e:
            print(f"invalid: {e}", file=sys.stderr)
            return 1
        print("ok")
    elif cmd == "get":
        if len(rest) != 1:
            return usage()
        try:
            show(lookup(tomllib.loads(read_text()), split_path(rest[0])))
        except KeyError:
            print(f"not set: {rest[0]}", file=sys.stderr)
            return 1
    elif cmd in ("set", "unset", "sync-monitors"):
        doc = Doc(read_text())
        if cmd == "set":
            if len(rest) != 2:
                return usage()
            parts = split_path(rest[0])
            if not parts:
                return usage()
            doc.set(parts, parse_cli_value(rest[1]))
        elif cmd == "unset":
            if len(rest) != 1:
                return usage()
            if not doc.unset(split_path(rest[0])):
                print(f"not set: {rest[0]}", file=sys.stderr)
                return 1
        else:
            sync_monitors(doc)
        try:
            write_text(doc.text())
        except tomllib.TOMLDecodeError as e:
            print(f"coel-settings: refusing to write, result would not parse: {e}", file=sys.stderr)
            return 1
        if do_apply:
            return apply()
    elif cmd == "edit":
        editor = os.environ.get("EDITOR", "nano")
        subprocess.run([editor, settings_path()])
        try:
            tomllib.loads(read_text())
        except tomllib.TOMLDecodeError as e:
            print(f"coel-settings: file has a syntax error, not applying: {e}", file=sys.stderr)
            return 1
        return apply()
    elif cmd == "apply":
        return apply()
    elif cmd == "render-hypridle":
        return cmd_render_hypridle(rest)
    else:
        return usage()
    return 0


def usage():
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
