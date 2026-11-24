# Keybind-driven "solve what's on my screen" workflow:
#   1. silent full-screen grim capture (all monitors, no preview/flash)
#   2. hand it to headless `claude -p`
#   3. copy the answer to the clipboard
#   4. tell the Quickshell bar (IpcHandler "assistant", sysPanel/Panel.qml)
#      to show "thinking" -> "done + short preview" (or "failed")
#
# Pressing the keybind again while a run is in flight cancels it.

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/coel-ask-screen"
QS_PATH="$HOME/.nixos/home/quickshell"
MODEL="${COEL_ASK_MODEL:-}"
# Forward proxy on jsgc-server (tinyproxy, Tailscale-only, Anthropic hosts
# only -- see server-dotfiles/home/claude-proxy.nix). Applied to the claude
# process alone. COEL_ASK_PROXY="" forces a direct connection.
PROXY="${COEL_ASK_PROXY-http://jsgc-server:3128}"
mkdir -p "$STATE_DIR"
# Screenshots may contain secrets: keep them private and short-lived.
chmod 700 "$STATE_DIR"

bar() { quickshell ipc -p "$QS_PATH" call assistant "$@" >/dev/null 2>&1 || true; }

# Re-press = cancel. The pidfile holds the previous run's process group.
PIDFILE="$STATE_DIR/pid"
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  # Children first (claude), then the script itself.
  pkill -P "$(cat "$PIDFILE")" 2>/dev/null || true
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
  bar clear
  exit 0
fi
echo $$ >"$PIDFILE"

IMG="$STATE_DIR/screen.png"
OUT="$STATE_DIR/answer.txt"
cleanup() { rm -f "$IMG" "$PIDFILE"; }
trap cleanup EXIT

bar working

# No -g: every output, stitched into one image.
if ! grim "$IMG"; then
  bar fail "screenshot failed"
  exit 1
fi

PROMPT="The file $IMG is a screenshot of my entire screen. Read it with the Read tool, find the question(s) or problem(s) on screen, and solve them.
Reply with the SHORTEST possible answer, nothing else: no preamble, no explanation, no restating the question, no markdown.
- Multiple choice: only the chosen letters/numbers, in on-screen order, comma separated (e.g. A, C, B). One per question.
- Numeric/short answer: just the value (with unit only if needed).
- Code or a command: just the minimal fix or command, no commentary.
- If there is no problem on screen, reply: nothing found
"

args=(-p "$PROMPT" --tools Read --allowedTools Read --add-dir "$STATE_DIR" --no-session-persistence)
[[ -n "$MODEL" ]] && args+=(--model "$MODEL")

# Use the proxy only if it answers within 2s; otherwise go direct so the
# keybind never fails just because the server is down or Tailscale is off.
envs=()
if [[ -n "$PROXY" ]]; then
  hostport="${PROXY#*://}"
  if timeout 2 bash -c "exec 3<>/dev/tcp/${hostport%%:*}/${hostport##*:}" 2>/dev/null; then
    envs=("HTTPS_PROXY=$PROXY" "https_proxy=$PROXY")
  fi
fi

# Run from the state dir so no project CLAUDE.md gets pulled in.
if (cd "$STATE_DIR" && env "${envs[@]}" claude "${args[@]}" >"$OUT" 2>"$STATE_DIR/err.txt") && [[ -s "$OUT" ]]; then
  wl-copy <"$OUT"
  # First non-empty line, whitespace-collapsed; the bar truncates further.
  PREVIEW=$(grep -m1 -v '^[[:space:]]*$' "$OUT" | tr -s '[:space:]' ' ' | cut -c1-60)
  bar "done" "$PREVIEW"
else
  bar fail "claude failed (see $STATE_DIR/err.txt)"
  exit 1
fi
