selection=$(fzf \
  --disabled \
  --multi \
  --prompt 'Search nixpkgs> ' \
  --bind 'change:reload:sleep 0.15; coel-package-search-query {q}' \
  --preview 'printf "Package: %s\nVersion: %s\n\n%s\n" {1} {2} {3..}' \
  --preview-label='tab: multi-select, alt-p: toggle description, alt-j/k: scroll' \
  --preview-label-pos='bottom' \
  --preview-window 'down:40%:wrap' \
  --bind 'alt-p:toggle-preview' \
  --bind 'alt-j:preview-down,alt-k:preview-up' \
  --color 'pointer:green,marker:green') || exit 0
# ^ Esc (130) or no match (1) just closes the window: that's cancelling, not
#   a failure worth holding it open for.

if [ -z "$selection" ]; then
  exit 0
fi

# From here on, hold the window open when done or if anything fails (see
# coel-show-done in home/rofi.nix).
trap 'coel-show-done --status "$?"' EXIT

copy_text=$(echo "$selection" | awk '{print "pkgs." $1}')
printf '%s' "$copy_text" | wl-copy

echo
echo "Copied to clipboard -- paste into home.nix or configuration.nix and rebuild:"
echo "$copy_text"
