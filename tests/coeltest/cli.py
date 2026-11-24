"""Command line front end:  python3 tests/run.py [SUITE|GROUP|GLOB ...] [options]

All the work is done by coeltest.runner (which returns data); this only parses arguments and prints.
"""

import argparse
import json
import sys
import threading

from . import runner
from .registry import REPO

ICON = {"passed": "✓", "failed": "✗", "error": "!", "skipped": "-"}


def _color(enabled):
    if not enabled:
        return lambda code, s: s
    codes = {"green": "32", "red": "31", "yellow": "33", "blue": "34", "dim": "2", "bold": "1"}
    return lambda code, s: "\033[%sm%s\033[0m" % (codes[code], s)


def build_parser():
    p = argparse.ArgumentParser(prog="run.py", description="Run the repo's tests. With no suite given, runs every fast suite.",
                                epilog="Suites can be ids (gcast-hls), group names (gcast, miracast, hyprland...) or globs (miracast-*).")
    p.add_argument("suites", nargs="*", metavar="SUITE", help="what to run (default: all except slow and manual)")
    p.add_argument("-l", "--list", action="store_true", help="list suites and whether they can run here, then exit")
    p.add_argument("-i", "--tui", action="store_true", help="open the interactive terminal UI")
    p.add_argument("-t", "--tag", action="append", default=[], help="only suites with this tag (unit, integration, slow); repeatable")
    p.add_argument("-x", "--exclude", action="append", default=[], help="skip suites matching this id/group/glob; repeatable")
    p.add_argument("--all", action="store_true", help="include slow suites (NixOS VM test, gstreamer integration)")
    p.add_argument("-j", "--jobs", type=int, default=4, help="suites to run in parallel (default 4)")
    p.add_argument("--nix", choices=runner.NIX_MODES, default="auto",
                   help="auto: wrap in nix-shell only when a tool is missing (default); always; never (skip suites that lack tools)")
    p.add_argument("--json", action="store_true", help="print the full report as JSON on stdout and nothing else")
    p.add_argument("-v", "--verbose", action="store_true", help="show every test, and the output of passing suites")
    p.add_argument("--check", action="store_true", help="verify every test file under tests/ is registered, then exit")
    return p


def cmd_list(args, c):
    rows = []
    for s in runner.discover():
        p = runner.plan(s, args.nix) if s.runnable else None
        if not s.runnable:
            env = "manual"
        elif p["skip"]:
            env = "cannot run here: " + p["skip"]
        else:
            env = "via nix-shell" if p["wrapped"] else "ready"
        rows.append((s, env))
    order = {}
    for s_, _ in rows:
        order.setdefault(s_.group, len(order))
    rows.sort(key=lambda r: order[r[0].group])          # one heading per group
    w = max(len(s.id) for s, _ in rows)
    group = None
    for s, env in rows:
        if s.group != group:
            group = s.group
            print(c("bold", group))
        print("  %-*s  %-11s %s  %s" % (w, s.id, ",".join(s.tags), c("dim", "[%s]" % env), s.title))
    return 0


def render(report, args, c, out=sys.stdout):
    for r in report["suites"]:
        mark = {"passed": c("green", ICON["passed"]), "failed": c("red", ICON["failed"]),
                "error": c("red", ICON["error"]), "skipped": c("yellow", ICON["skipped"])}[r["status"]]
        cnt = r["counts"]
        detail = "%d passed" % cnt["passed"] + (", %d failed" % (cnt["failed"] + cnt["error"]) if cnt["failed"] + cnt["error"] else "") \
            + (", %d skipped" % cnt["skipped"] if cnt["skipped"] else "")
        if r["status"] == "skipped" and not r["tests"]:
            detail = r["reason"]
        elif r["status"] == "error" and r["reason"]:
            detail = r["reason"]
        print("%s %-22s %s %s" % (mark, r["id"], detail, c("dim", "%.1fs%s" % (r["duration"], " (nix-shell)" if r["wrapped"] else ""))), file=out)
        if args.verbose:
            for t in r["tests"]:
                print("    %s %s" % (ICON[t["status"]], t["name"]), file=out)
    bad = [r for r in report["suites"] if r["status"] in ("failed", "error")]
    if bad:
        print("\n" + c("red", "failures"), file=out)
        for r in bad:
            for t in r["tests"]:
                if t["status"] in ("failed", "error"):
                    print(c("bold", "[%s] %s" % (r["id"], t["name"])), file=out)
                    print("    " + (t["message"] or "(no message)").strip().replace("\n", "\n    "), file=out)
            if r["reason"] and not r["tests"]:
                print(c("bold", "[%s]" % r["id"]) + " " + r["reason"], file=out)
            if r["status"] == "error" and r["output"]:
                print("    " + r["output"][-1500:].replace("\n", "\n    "), file=out)
    if args.verbose:
        for r in report["suites"]:
            if r["status"] == "passed" and r["output"]:
                print("\n" + c("dim", "output of %s:" % r["id"]) + "\n" + r["output"][-2000:], file=out)
    s = report["summary"]
    line = "%d suites: %d passed, %d failed, %d skipped  ·  %d tests passed, %d failed%s  ·  %.1fs" % (
        s["suites"], s["suites_passed"], s["suites_failed"], s["suites_skipped"], s["passed"], s["failed"] + s["error"],
        (", %d skipped" % s["skipped"]) if s["skipped"] else "", report["duration"])
    print("\n" + (c("green", line) if s["ok"] else c("red", line)), file=out)


def main(argv=None):
    args = build_parser().parse_args(argv)
    c = _color(sys.stdout.isatty() and not args.json)
    if args.check:
        bad = runner.unregistered()
        for b in bad:
            print("not registered: tests/" + b)
        print("ok" if not bad else "%d unregistered" % len(bad))
        return 1 if bad else 0
    if args.list:
        return cmd_list(args, c)
    if args.tui:
        from . import tui
        return tui.main(args)

    suites = runner.select(args.suites, args.tag, args.exclude, include_slow=args.all)
    if not suites:
        print("no suites match", file=sys.stderr)
        return 2
    lock = threading.Lock()

    def live(ev):
        if ev["type"] == "done" and not args.json and sys.stdout.isatty():
            with lock:
                r = ev["result"]
                sys.stdout.write(c("dim", "  finished %s: %s\n" % (r["id"], r["status"])))

    report = runner.run(suites, jobs=args.jobs, nix=args.nix, on_event=live if not args.verbose else None)
    if args.json:
        json.dump(report, sys.stdout, indent=2)
        print()
    else:
        render(report, args, c)
    return 0 if report["summary"]["ok"] else 1
