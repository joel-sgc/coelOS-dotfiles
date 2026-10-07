#!/usr/bin/env bash
# Screen share picker for xdg-desktop-portal-hyprland. The portal runs this as
# `screencopy { custom_picker_binary = ... }` (see home/os-commands.nix, which
# wraps this file as `coel-share-picker`) and reads ONE line from its stdout:
#   [SELECTION]<r?>/screen:NAME | /window:ID | /region:NAME@x,y,w,h
# -- or nothing at all, which means cancelled. Anything else on stdout (logs,
# warnings) would corrupt that, so Quickshell's output is thrown away and its
# answer comes back through a temp file instead (see SharePicker.qml).
#
# Reads XDPH_WINDOW_SHARING_LIST from the environment (inherited from the
# portal) and `--allow-token` (pre-ticks "remember") from the arguments.

# the portal's systemd user service doesn't have our profile on PATH
PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:$PATH"

out=$(mktemp)
trap 'rm -f "$out"' EXIT

export COEL_PICKER_OUT="$out"
case " $* " in
  *" --allow-token "*) export COEL_PICKER_TOKEN=1 ;;
esac

# timeout: the portal blocks on us, so never let a wedged picker hang it forever
timeout 600 quickshell -p "$HOME/.nixos/home/quickshell/screenshare-shell.qml" >/dev/null 2>&1 || true

# pass through only a well-formed answer
grep -a '^\[SELECTION\]' "$out" || true
