#!/bin/bash

sudo pacman -Syu --noconfirm

yay -Syu

exec ~/.coelOS-dotfiles/bin/show-done.sh
