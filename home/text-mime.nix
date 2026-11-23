# Every MIME type that should open in micro (in a Ghostty window; see
# home/micro.nix). One list, used twice: micro.desktop declares them as the
# types it handles, and home/mimeapps.nix makes micro the default for them.
#
# Dolphin/KDE show a bare "enter a command" prompt, with no app list, for any
# type that has no explicit default -- application/json, yaml, toml, shell
# scripts, logs, csv, ... all fell into that. Detected types are the
# shared-mime-info names (`xdg-mime query filetype <file>`).
[
  "text/plain"
  "application/x-zerosize" # an empty file, e.g. a freshly created .env
  "text/markdown"
  "text/x-log"
  "text/csv"
  "text/tab-separated-values"
  "text/x-readme"
  "text/x-diff"
  "text/x-patch"

  # data / config
  "application/json"
  "application/x-ndjson"
  "application/yaml"
  "application/x-yaml"
  "application/toml"
  "text/x-toml"
  "application/xml"
  "text/xml"
  "application/sql"
  "text/x-sql"
  "text/x-systemd-unit"
  "text/x-dbus-service"
  "application/x-desktop"
  "application/x-shellscript"
  "text/x-makefile"
  "text/x-cmake"

  # source code
  "text/javascript"
  "application/javascript"
  "text/css"
  "text/x-python"
  "text/x-script.python"
  "text/x-lua"
  "text/rust"
  "text/x-go"
  "text/x-qml"
  "text/x-csrc"
  "text/x-chdr"
  "text/x-c++src"
  "text/x-c++hdr"
  "text/x-java"
  "text/x-typescript"
  "text/x-tex"
  "application/x-php"
  "application/x-perl"
  "application/x-ruby"
  # shared-mime-info files *.ts as Qt Linguist and *.tsx as Tiled tilesets;
  # here those are TypeScript.
  "text/vnd.trolltech.linguist"
  "application/x-tiled-tsx"
]
