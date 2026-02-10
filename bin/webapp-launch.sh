#!/bin/bash

URL="$1"
shift

CHROMIUM=$(command -v chromium || command -v chromium-browser)

if [ -z "$CHROMIUM" ]; then
	echo "Chromium not found in PATH"
	exit 1
fi

exec setsid "$CHROMIUM" --app="$URL" "$@"
