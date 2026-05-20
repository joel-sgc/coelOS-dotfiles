#!/usr/bin/zsh

# Base directory
BASE_DIR="$HOME/.coelOS-dotfiles"

# Optional argument
COLORS_ENV="$1"

loadenv() {
  local file

  if [[ -n "$COLORS_ENV" && -f "$BASE_DIR/$COLORS_ENV" ]]; then
    file="$BASE_DIR/$COLORS_ENV"
  elif [[ -f "$BASE_DIR/theme/colors.env" ]]; then
    file="$BASE_DIR/theme/colors.env"
  else
    echo "No env file found"
    return 1
  fi

  set -a
  source "$file"
  set +a
}

loadenv
echo "${BG_BASE:-BG_BASE not set}"