#!/bin/bash

# Display a "Done!" message with a spinner and wait for user to press any key.
# Used by various install scripts to indicate completion.

TITLE="$1"

if [[ -z "$1" ]]; then
	TITLE="Done! Press any key to close..."
fi

echo
gum spin --spinner "globe" --title "$TITLE" -- bash -c 'read -n 1 -s'
