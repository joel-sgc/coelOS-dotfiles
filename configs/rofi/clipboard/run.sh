#!/bin/bash
clip_count=$(clipvault list | wc -l)
if (( clip_count < 10)); then
	lines=$clip_count
else 
	lines=10
fi

PREVIEW=true rofi -modi clipboard:~/.coelOS-dotfiles/configs/rofi/clipboard/clipvault-rofi-img.sh -show clipboard -theme-str "window {width: 1280px;} listview {lines: $lines; fixed-height: true;}" -lines $lines -no-fixed-num-lines -show-icons
