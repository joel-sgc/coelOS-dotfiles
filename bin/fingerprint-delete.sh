#!/usr/bin/env bash
set -e

# Ensure sudo auth is cached BEFORE touching fprintd
sudo -v

# Small delay prevents device re-claim race
sleep 0.2

# Delete prints without re-triggering enrollment
sudo rm -rf /var/lib/fprint/*

exec ~/.coelOS-dotfiles/bin/show-done.sh