#!/bin/bash
# Updated to match the actual app name your system is broadcasting!
TARGET_APP="swayosd"

# Use awk to parse the human-readable text block directly
TARGET_IDS=$(makoctl list | awk -v app="$TARGET_APP" '
/^Notification/ { 
    # Grab the ID number (e.g., "156:") and strip the colon
    id=$2; 
    sub(":", "", id); 
}
/^[ \t]*App name:/ { 
    # Grab the whole line, strip the prefix spaces and "App name: " label
    name=$0; 
    sub(/^[ \t]*App name: /, "", name); 
    
    # If the remaining text matches our target, print the ID
    if (name == app) { 
        print id; 
    }
}')

# Loop through and dismiss any found IDs
for id in $TARGET_IDS; do
    if [ -n "$id" ]; then
        makoctl dismiss -n "$id"
    fi
done