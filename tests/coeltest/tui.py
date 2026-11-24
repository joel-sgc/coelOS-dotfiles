"""Terminal UI (curses, stdlib only):  python3 tests/run.py --tui

  select   j/k or arrows move · space toggle · a all · d defaults · n none · g toggle group · / filter · enter run · q quit
  run      live status of every selected suite
  results  j/k move · enter details · r rerun failed · b back to the list · q quit
  details  j/k or PgUp/PgDn scroll · esc/q back
"""

import curses
import locale
import threading
import time

from . import runner

SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


class State:
    def __init__(self, args):
        self.args = args
        suites = runner.discover()
        order = {}
        for x in suites:
            order.setdefault(x.group, len(order))
        self.suites = sorted(suites, key=lambda x: order[x.group])     # one heading per group
        self.selected = {s.id for s in runner.select(include_slow=bool(args.all))}
        self.cursor = 0
        self.filter = ""
        self.mode = "select"               # select | run | results | detail
        self.status = {}                   # suite id -> "queued" | "running" | result dict
        self.report = None
        self.thread = None
        self.lock = threading.Lock()
        self.scroll = 0
        self.rcursor = 0
        self.detail_lines = []
        self.message = ""

    def visible(self):
        f = self.filter.lower()
        rows, group = [], None
        for s in self.suites:
            if f and f not in (s.id + " " + s.title + " " + s.group + " " + " ".join(s.tags)).lower():
                continue
            if s.group != group:
                group = s.group
                rows.append(("group", group))
            rows.append(("suite", s))
        return rows

    def selectable(self):
        return [r[1] for r in self.visible() if r[0] == "suite" and r[1].runnable]


def start_run(st, ids):
    suites = [runner.get(i) for i in ids]
    st.status = {s.id: "queued" for s in suites}
    st.report = None
    st.mode = "run"
    st.rcursor = 0

    def on_event(ev):
        with st.lock:
            st.status[ev["suite"]] = "running" if ev["type"] == "start" else ev["result"]

    def work():
        rep = runner.run(suites, jobs=st.args.jobs, nix=st.args.nix, on_event=on_event)
        with st.lock:
            st.report = rep

    st.thread = threading.Thread(target=work, daemon=True)
    st.thread.start()


def put(win, y, x, text, attr=0):
    h, w = win.getmaxyx()
    if 0 <= y < h and x < w:
        try:
            win.addstr(y, x, text[: max(0, w - x - 1)], attr)
        except curses.error:
            pass


def detail_for(r):
    lines = ["%s  [%s]  %s" % (r["id"], r["status"], r["title"]), ""]
    if r["reason"]:
        lines += ["reason: " + r["reason"], ""]
    if r["command"]:
        lines += ["command: " + " ".join(r["command"])[:300], ""]
    for t in r["tests"]:
        lines.append("  %s %s" % ({"passed": "✓", "failed": "✗", "error": "!", "skipped": "-"}[t["status"]], t["name"]))
        if t["status"] in ("failed", "error") and t["message"]:
            lines += ["      " + ln for ln in t["message"].rstrip().splitlines()]
    if r["output"]:
        lines += ["", "output:"] + ["  " + ln for ln in r["output"].splitlines()[-200:]]
    return lines


def draw(scr, st, colors):
    scr.erase()
    h, w = scr.getmaxyx()
    ok, bad, warn, head, dim = colors
    spin = SPIN[int(time.time() * 12) % len(SPIN)]

    if st.mode == "select":
        put(scr, 0, 1, "coel tests", head | curses.A_BOLD)
        put(scr, 0, 13, "space toggle · a all · d defaults · n none · g group · / filter · enter run · q quit", dim)
        if st.filter or st.message:
            put(scr, 1, 1, ("filter: " + st.filter) if st.filter else st.message, warn)
        rows = st.visible()
        sel = st.selectable()
        cur = sel[min(st.cursor, len(sel) - 1)] if sel else None
        y = 3
        for kind, item in rows:
            if y >= h - 2:
                break
            if kind == "group":
                put(scr, y, 1, item, head | curses.A_BOLD)
            else:
                s = item
                p = runner.plan(s, st.args.nix) if s.runnable else None
                box = "[x]" if s.id in st.selected else "[ ]"
                if not s.runnable:
                    box = " · "
                line = "%s %-22s %-17s %s" % (box, s.id, ",".join(s.tags), s.title)
                attr = dim if not s.runnable or (p and p["skip"]) else 0
                if cur is s:
                    attr |= curses.A_REVERSE
                put(scr, y, 3, line, attr)
                if p and p["wrapped"]:
                    put(scr, y, 3 + len(line) + 1, "nix-shell", dim)
                elif p and p["skip"]:
                    put(scr, y, 3 + len(line) + 1, "cannot run: " + p["skip"][:40], warn)
                elif not s.runnable:
                    put(scr, y, 3 + len(line) + 1, "manual", dim)
            y += 1
        put(scr, h - 1, 1, "%d selected" % len([i for i in st.selected if runner.get(i)]), dim)

    elif st.mode in ("run", "results"):
        with st.lock:
            status = dict(st.status)
            report = st.report
        running = report is None
        title = "running… " + spin if running else "results"
        put(scr, 0, 1, "coel tests — " + title, head | curses.A_BOLD)
        if not running:
            put(scr, 0, 30, "j/k move · enter details · r rerun failed · b back · q quit", dim)
        ids = list(status)
        for i, sid in enumerate(ids):
            y = 2 + i
            if y >= h - 3:
                break
            v = status[sid]
            if isinstance(v, dict):
                sym, col = {"passed": ("✓", ok), "failed": ("✗", bad), "error": ("!", bad), "skipped": ("-", warn)}[v["status"]]
                c = v["counts"]
                txt = "%d passed" % c["passed"] + (", %d failed" % (c["failed"] + c["error"]) if c["failed"] + c["error"] else "")
                if v["status"] == "skipped" and not v["tests"]:
                    txt = v["reason"]
                elif v["reason"] and v["status"] == "error":
                    txt = v["reason"]
                row = "%s %-22s %s  %.1fs" % (sym, sid, txt, v["duration"])
            else:
                col = warn if v == "running" else dim
                row = "%s %-22s %s" % (spin if v == "running" else "·", sid, v)
            attr = col | (curses.A_REVERSE if (not running and i == st.rcursor) else 0)
            put(scr, y, 2, row, attr)
        if report:
            s = report["summary"]
            line = "%d suites: %d passed, %d failed, %d skipped · %d tests passed, %d failed · %.1fs" % (
                s["suites"], s["suites_passed"], s["suites_failed"], s["suites_skipped"], s["passed"], s["failed"] + s["error"], report["duration"])
            put(scr, h - 2, 1, line, ok if s["ok"] else bad)

    elif st.mode == "detail":
        put(scr, 0, 1, "details — j/k scroll · esc back", dim)
        for i, ln in enumerate(st.detail_lines[st.scroll: st.scroll + h - 3]):
            col = bad if ln.lstrip().startswith(("✗", "!")) else (ok if ln.lstrip().startswith("✓") else 0)
            put(scr, 2 + i, 1, ln, col)
    scr.refresh()


def handle(scr, st, key):
    """Returns False to quit."""
    h, _ = scr.getmaxyx()
    if st.mode == "select":
        sel = st.selectable()
        if key in (ord("q"), 27) and not st.filter:
            return False
        if key in (curses.KEY_DOWN, ord("j")) and sel:
            st.cursor = min(len(sel) - 1, st.cursor + 1)
        elif key in (curses.KEY_UP, ord("k")) and sel:
            st.cursor = max(0, st.cursor - 1)
        elif key == ord(" ") and sel:
            s = sel[min(st.cursor, len(sel) - 1)]
            st.selected.symmetric_difference_update({s.id})
        elif key == ord("a"):
            st.selected = {s.id for s in sel}
        elif key == ord("d"):
            st.selected = {s.id for s in runner.select(include_slow=False) if s in sel}
        elif key == ord("n"):
            st.selected = set()
        elif key == ord("g") and sel:
            s = sel[min(st.cursor, len(sel) - 1)]
            grp = {x.id for x in sel if x.group == s.group}
            if grp <= st.selected:
                st.selected -= grp
            else:
                st.selected |= grp
        elif key == ord("/"):
            curses.curs_set(1)
            curses.echo()
            scr.timeout(-1)
            put(scr, 1, 1, "filter: " + " " * 40)
            scr.move(1, 9)
            try:
                st.filter = scr.getstr(1, 9, 40).decode().strip()
            except Exception:
                st.filter = ""
            curses.noecho()
            curses.curs_set(0)
            scr.timeout(100)
            st.cursor = 0
        elif key == 27 and st.filter:
            st.filter = ""
        elif key in (10, 13, curses.KEY_ENTER):
            ids = [s.id for s in st.suites if s.id in st.selected and s.runnable]
            if ids:
                start_run(st, ids)
            else:
                st.message = "nothing selected"
    elif st.mode == "run":
        if key == ord("q") and st.report is not None:
            return False
        if st.report is not None:
            st.mode = "results"
    elif st.mode == "results":
        ids = list(st.status)
        if key in (ord("q"),):
            return False
        elif key in (curses.KEY_DOWN, ord("j")):
            st.rcursor = min(len(ids) - 1, st.rcursor + 1)
        elif key in (curses.KEY_UP, ord("k")):
            st.rcursor = max(0, st.rcursor - 1)
        elif key in (10, 13, curses.KEY_ENTER) and ids:
            r = st.status[ids[st.rcursor]]
            st.detail_lines = detail_for(r) if isinstance(r, dict) else ["(no result)"]
            st.scroll = 0
            st.mode = "detail"
        elif key == ord("b"):
            st.mode = "select"
        elif key == ord("r"):
            failed = [i for i, v in st.status.items() if isinstance(v, dict) and v["status"] in ("failed", "error")]
            if failed:
                start_run(st, failed)
    elif st.mode == "detail":
        if key in (27, ord("q"), curses.KEY_LEFT, ord("b")):
            st.mode = "results"
        elif key in (curses.KEY_DOWN, ord("j")):
            st.scroll = min(max(0, len(st.detail_lines) - 1), st.scroll + 1)
        elif key in (curses.KEY_UP, ord("k")):
            st.scroll = max(0, st.scroll - 1)
        elif key == curses.KEY_NPAGE:
            st.scroll = min(max(0, len(st.detail_lines) - 1), st.scroll + h - 4)
        elif key == curses.KEY_PPAGE:
            st.scroll = max(0, st.scroll - (h - 4))
    return True


def _run(scr, args):
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    for i, c in enumerate((curses.COLOR_GREEN, curses.COLOR_RED, curses.COLOR_YELLOW, curses.COLOR_BLUE, 8), start=1):
        curses.init_pair(i, c if c < curses.COLORS else curses.COLOR_WHITE, -1)
    colors = tuple(curses.color_pair(i) for i in range(1, 6))
    scr.timeout(100)
    st = State(args)
    while True:
        if st.mode == "run" and st.report is not None:
            st.mode = "results"                  # finished: show the results without waiting for a key
        draw(scr, st, colors)
        key = scr.getch()
        if key == -1:
            continue
        if key == curses.KEY_RESIZE:
            continue
        st.message = ""
        if not handle(scr, st, key):
            break
    return st


def main(args):
    locale.setlocale(locale.LC_ALL, "")
    final = curses.wrapper(lambda scr: _run(scr, args))
    rep = final.report
    return 0 if (rep is None or rep["summary"]["ok"]) else 1
