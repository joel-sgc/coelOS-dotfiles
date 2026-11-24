"""Run suites and return DATA. Nothing in here prints, reads the terminal or exits.

    import coeltest
    report = coeltest.run(coeltest.select(["hyprland-*"]))     # -> dict, see below
    report["summary"]["failed"]

Result of one suite (`run_suite`):
    {"id", "title", "group", "kind", "status": passed|failed|error|skipped,
     "duration": seconds, "counts": {"passed", "failed", "error", "skipped"},
     "tests": [{"name", "status", "duration", "message"}], "output": "<captured stdout+stderr>",
     "reason": "<why skipped / why it errored>", "command": [...], "wrapped": bool}
Result of `run`: {"suites": [suite results], "summary": {...totals...}, "duration": seconds}
"""

import fnmatch
import importlib.util
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

from .registry import REPO, SUITES, SUPPORT, TESTS, Suite

MARK = "@@COELTEST@@"
WORKERS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "workers")
NIX_MODES = ("auto", "always", "never")


# ------------------------------------------------------------------ discovery / selection
def discover():
    return list(SUITES)


def get(suite_id):
    for s in SUITES:
        if s.id == suite_id:
            return s
    return None


def select(patterns=(), tags=(), exclude=(), include_slow=False, include_manual=False):
    """Suites matching any of `patterns` (suite id, group name, or fnmatch glob; none = the default set)."""
    def hit(s, pats):
        return any(fnmatch.fnmatchcase(s.id, p) or fnmatch.fnmatchcase(s.group, p) for p in pats)
    chosen = []
    for s in SUITES:
        if patterns:
            if not hit(s, patterns):
                continue
        elif not s.default and not (include_slow and s.runnable):
            continue
        if not patterns and not include_slow and "slow" in s.tags:
            continue
        if not s.runnable and not include_manual:
            continue
        if tags and not (set(tags) & set(s.tags)):
            continue
        if exclude and hit(s, exclude):
            continue
        chosen.append(s)
    return chosen


def unregistered():
    """Test-looking files under tests/ that no suite (or SUPPORT entry) accounts for."""
    known = {s.path for s in SUITES if not s.repo_path} | SUPPORT
    known_dirs = {s.path for s in SUITES if s.kind == "manual" and not s.repo_path}
    out = []
    for root, dirs, files in os.walk(TESTS):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), TESTS)
            if rel in known or any(rel.startswith(d + "/") for d in known_dirs):
                continue
            if rel.startswith("coeltest/") or rel == "run.py" or f.endswith((".md", ".pyc")):
                continue
            if (f.startswith("test_") and f.endswith(".py")) or f.endswith(("_test.lua", ".test.js", "-test.nix", "_test.py")) \
                    or f.startswith(("integration.", "run-")) or f.endswith("_e2e.sh"):
                out.append(rel)
    return sorted(out)


# ------------------------------------------------------------------ environment
def _importable(mod):
    return importlib.util.find_spec(mod) is not None


def missing_requirements(suite):
    miss = [c for c in suite.cmds if shutil.which(c) is None]
    miss += [m for m in suite.pymods if not _importable(m)]
    return miss


def build_command(suite, wrapped=False):
    py = "python3" if wrapped else sys.executable
    fmt = {"repo": REPO, "tests": TESTS}
    if suite.kind == "python":
        return [py, os.path.join(WORKERS, "pyworker.py"), suite.abspath]
    if suite.kind == "lua":
        return ["lua", os.path.join(WORKERS, "lua_driver.lua"), suite.abspath]
    if suite.kind == "node":
        return ["node", os.path.join(WORKERS, "node_driver.js"), suite.abspath]
    if suite.kind == "shell":
        return ["bash", suite.abspath, *suite.args]
    if suite.kind == "nixos":
        return [part.replace("{repo}", fmt["repo"]).replace("{tests}", fmt["tests"]) for part in suite.command]   # not str.format: the nix expression has braces
    raise ValueError("suite %s (%s) is not runnable" % (suite.id, suite.kind))


def plan(suite, nix="auto"):
    """How a suite would run: {"command", "wrapped", "skip": None | reason}."""
    miss = missing_requirements(suite)
    have_nix = shutil.which("nix-shell") is not None
    wrap = bool(suite.nix) and have_nix and (nix == "always" or (nix == "auto" and miss))
    if miss and not wrap:
        hint = " (try --nix auto, or install: %s)" % ", ".join(suite.nix) if suite.nix else ""
        return {"command": [], "wrapped": False, "skip": "missing: " + ", ".join(miss) + hint}
    cmd = build_command(suite, wrapped=wrap)
    if wrap:
        cmd = ["nix-shell", "-p", *suite.nix, "--run", shlex.join(cmd)]
    return {"command": cmd, "wrapped": wrap, "skip": None}


# ------------------------------------------------------------------ running
def _blank(suite):
    return {"id": suite.id, "title": suite.title, "group": suite.group, "kind": suite.kind, "tags": list(suite.tags),
            "status": "skipped", "duration": 0.0, "counts": {"passed": 0, "failed": 0, "error": 0, "skipped": 0},
            "tests": [], "output": "", "reason": "", "command": [], "wrapped": False}


def _worker_json(stdout):
    for line in reversed(stdout.splitlines()):
        if line.startswith(MARK):
            try:
                return json.loads(line[len(MARK):]), stdout[:stdout.rfind(line)]
            except ValueError:
                return None, stdout
    return None, stdout


def _tests_from(suite, data, rc, output):
    if suite.kind == "python":
        return data["tests"]
    if suite.kind in ("lua", "node"):
        return [{"name": r.get("name", "?"), "status": "passed" if r.get("ok") else "failed",
                 "message": r.get("error", "") or "", "duration": 0} for r in data.get("results", [])]
    return [{"name": suite.id, "status": "passed" if rc == 0 else "failed", "message": "" if rc == 0 else output[-4000:], "duration": 0}]


def run_suite(suite, nix="auto", timeout=None):
    """Run one suite and return its result dict. Never raises for test failures."""
    res = _blank(suite)
    if not suite.runnable:
        res["reason"] = suite.note or "manual suite"
        return res
    p = plan(suite, nix)
    res["command"], res["wrapped"] = p["command"], p["wrapped"]
    if p["skip"]:
        res["reason"] = p["skip"]
        return res
    t0 = time.time()
    tmp = tempfile.mkdtemp(prefix="coeltest-")
    try:
        env = dict(os.environ)
        if suite.prepare:
            env.update(suite.prepare(tmp))
        try:
            cp = subprocess.run(p["command"], capture_output=True, text=True, cwd=REPO, env=env, timeout=timeout or suite.timeout)
            rc, out, err = cp.returncode, cp.stdout, cp.stderr
        except subprocess.TimeoutExpired as e:
            res.update(status="error", reason="timed out after %ds" % (timeout or suite.timeout),
                       output=((e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")))
            res["duration"] = round(time.time() - t0, 3)
            return res
        data, log = _worker_json(out)
        res["output"] = (log + err).strip()
        if suite.kind in ("python", "lua", "node") and data is None:
            res.update(status="error", reason="the test worker produced no result (exit %d)" % rc)
            res["tests"] = [{"name": "worker", "status": "error", "message": res["output"][-4000:], "duration": 0}]
        else:
            res["tests"] = _tests_from(suite, data, rc, res["output"] if suite.kind in ("shell", "nixos") else "")
        for t in res["tests"]:
            res["counts"][t["status"]] = res["counts"].get(t["status"], 0) + 1
        c = res["counts"]
        if res["status"] != "error":
            res["status"] = "failed" if (c["failed"] or c["error"]) else ("skipped" if res["tests"] and c["skipped"] == len(res["tests"]) else "passed")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        res["duration"] = round(time.time() - t0, 3)
    return res


def summarize(results, duration=0.0):
    s = {"suites": len(results), "suites_passed": 0, "suites_failed": 0, "suites_skipped": 0,
         "passed": 0, "failed": 0, "error": 0, "skipped": 0, "ok": True}
    for r in results:
        key = {"passed": "suites_passed", "skipped": "suites_skipped"}.get(r["status"], "suites_failed")
        s[key] += 1
        for k in ("passed", "failed", "error", "skipped"):
            s[k] += r["counts"].get(k, 0)
    s["ok"] = s["suites_failed"] == 0
    return s


def run(suites, jobs=4, nix="auto", on_event=None, timeout=None):
    """Run suites (in parallel) and return {"suites": [...], "summary": {...}, "duration": s}.
    `on_event(dict)` (optional) is called with {"type": "start"|"done", "suite": id[, "result": dict]} from worker threads."""
    suites = list(suites)
    t0 = time.time()
    results = {}

    def one(s):
        if on_event:
            on_event({"type": "start", "suite": s.id})
        r = run_suite(s, nix=nix, timeout=timeout)
        results[s.id] = r
        if on_event:
            on_event({"type": "done", "suite": s.id, "result": r})
        return r

    with ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        list(ex.map(one, suites))
    ordered = [results[s.id] for s in suites]
    dur = round(time.time() - t0, 3)
    return {"suites": ordered, "summary": summarize(ordered, dur), "duration": dur}
