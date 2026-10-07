{ lib, ... }:

{
  # Which keyring apps use is whatever the `default` alias points at, and the
  # only keyring pam_gnome_keyring auto-unlocks at login is the one named
  # `login`. Some app had created a separate "Default keyring" with its own
  # password and made it the default, so every secret lookup raised an unlock
  # prompt. Pin the alias to `login` (the contents of the `default` file are
  # just the keyring's file name, without extension).
  #
  # Only touches the file when it differs, and only if the keyring dir exists
  # (a fresh machine gets `login` as default from gnome-keyring itself on
  # first PAM login). A running daemon keeps its in-memory alias until the
  # next login; for the current session use:
  #   gdbus call --session --dest org.freedesktop.secrets \
  #     --object-path /org/freedesktop/secrets \
  #     --method org.freedesktop.Secret.Service.SetAlias default \
  #     /org/freedesktop/secrets/collection/login
  #
  # Secrets that were stored in the old Default keyring are NOT moved by this
  # (e.g. re-run coel-vpn-set-password for the GlobalProtect password).
  home.activation.keyringDefaultIsLogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    keyrings="$HOME/.local/share/keyrings"
    if [ -d "$keyrings" ] && [ "$(cat "$keyrings/default" 2>/dev/null)" != "login" ]; then
      $DRY_RUN_CMD sh -c 'printf login > "$1"' _ "$keyrings/default"
    fi
  '';
}
