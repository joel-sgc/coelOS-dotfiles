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
  --color 'pointer:green,marker:green')

if [ -z "$selection" ]; then
  exit 0
fi

copy_text=$(echo "$selection" | awk '{print "pkgs." $1}')
printf '%s' "$copy_text" | wl-copy

echo
echo "Copied to clipboard -- paste into home.nix or configuration.nix and rebuild:"
echo "$copy_text"
exec coel-show-done
