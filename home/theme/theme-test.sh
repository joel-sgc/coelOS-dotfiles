echo "== Ghostty palette (reading this in Ghostty confirms it) =="
for i in $(seq 0 15); do printf "\033[48;5;%sm  \033[0m" "$i"; done
echo
echo

echo "== Mako =="
notify-send -a "CoelOS" "Theme Test" "Normal notification -- border should be One Dark blue."
sleep 2
notify-send -a "CoelOS" -u critical "Theme Test" "Critical notification -- border should be One Dark error red."
sleep 1
echo

echo "== Rofi =="
printf "Row one\nRow two\nRow three\n" | rofi -dmenu -i -p "Theme Test (Esc to close)"
echo

echo "== Hyprland window borders =="
echo "Compare this window's border against an unfocused one (Super+arrow to switch focus)."
echo

read -r -p "Test hyprlock too? Screen will lock, you'll need your password to get back in. [y/N] " ans
case "$ans" in
  [yY]*) hyprlock ;;
  *) echo "Skipped hyprlock." ;;
esac
