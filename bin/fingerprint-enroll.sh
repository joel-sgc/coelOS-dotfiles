#!/usr/bin/env bash
sudo pkill fprintd
sudo fprintd-enroll "$USER"
exec ~/.coelOS-dotfiles/bin/show-done.sh
