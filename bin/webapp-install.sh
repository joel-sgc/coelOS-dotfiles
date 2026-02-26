#!/bin/bash

set -e

if [ "$#" -lt 3 ]; then
  echo -e "\e[32mLet's create a new web app you can start with the app launcher.\n\e[0m"
  APP_NAME=$(gum input --prompt "Name> " --placeholder "My favorite web app")
  APP_URL=$(gum input --prompt "URL> " --placeholder "https://example.com")
  CUSTOM_EXEC=""
  MIME_TYPES=""
  INTERACTIVE_MODE=true
else
  APP_NAME="$1"
  APP_URL="$2"
  CUSTOM_EXEC="$4" # Optional custom exec command
  MIME_TYPES="$5"  # Optional mime types
  INTERACTIVE_MODE=false
fi

# Ensure valid execution
if [[ -z "$APP_NAME" || -z "$APP_URL" ]]; then
  echo "You must set app name, app URL!"
  exit 1
fi

# Use custom exec if provided, otherwise default behavior
if [[ -n $CUSTOM_EXEC ]]; then
  EXEC_COMMAND="$CUSTOM_EXEC"
else
  EXEC_COMMAND="/home/joelsgc/.coelOS-dotfiles/bin/webapp-launch.sh $APP_URL"
fi

# Create application .desktop file
mkdir -p ~/.local/share/applications
DESKTOP_FILE="$HOME/.local/share/applications/$APP_NAME.desktop"

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$APP_NAME
Comment=$APP_NAME
Exec=$EXEC_COMMAND
Terminal=false
Type=Application
StartupNotify=true
EOF

# Add mime types if provided
if [[ -n $MIME_TYPES ]]; then
  echo "MimeType=$MIME_TYPES" >>"$DESKTOP_FILE"
fi

chmod +x "$DESKTOP_FILE"

if [[ $INTERACTIVE_MODE == true ]]; then
  echo -e "You can now find $APP_NAME using the app launcher (SUPER + SPACE)\n"
fi
