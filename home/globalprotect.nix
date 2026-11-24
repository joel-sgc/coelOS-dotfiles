{
  pkgs,
  ...
}:

let
  portal = "secureaccess.luc.edu";
  username = "jgutierrez11@luc.edu";

  # Secret Service (libsecret / `secret-tool`) attributes for the stored LUC
  # portal password. On this box org.freedesktop.secrets is owned by
  # gnome-keyring (PAM-unlocked at login), so we go through libsecret. The lookup key
  # is the (service, account) pair below.
  secretService = "coel-vpn";
  secretAccount = username;
  secretLabel = "LUC GlobalProtect";

  # Separate keyring service for the TOTP seed backing the "Enter Your
  # Microsoft verification code" / "Challenge:" prompt -- kept apart from
  # the portal password so forgetting/rotating one doesn't touch the other.
  # This is the raw secret Microsoft shows once at enrollment time (the
  # "can't scan the QR code? set up manually" option) -- store it once with
  # coel-vpn-set-mfa-secret and coel-vpn-connect generates a fresh code
  # itself from then on, same as the Microsoft Authenticator app would, just
  # without needing to look at a phone. It's as sensitive as the password:
  # anyone who has it can generate valid codes indefinitely. Entirely
  # optional -- without it, coel-vpn-connect falls back to the existing
  # interactive stdin prompt.
  mfaSecretService = "coel-vpn-mfa";
  mfaSecretLabel = "LUC GlobalProtect MFA seed";

  # Driven wrapper around `openconnect --protocol=gp` (see
  # modules/globalprotect-openconnect.nix for the root-privileged half this
  # hands off to, and modules/globalprotect/openconnect-hipreport.sh for the
  # honest HIP report it sends). The vendor PAN client this used to drive
  # (PanGPS/PanGPA, its FHS sandbox, gp-connect.exp) is gone -- removed once
  # this backend was proven working; see [[project_globalprotect_luc]]. LUC
  # auth is plain username+password against the portal (no SAML) followed
  # by a gateway OTP challenge -- see
  # home/globalprotect/openconnect-authenticate.exp for the reverse-engineered
  # flow (same prompt sequence either client uses, since it's rendered by
  # LUC's own portal form).
  #
  # Two phases:
  #   1. Unprivileged: openconnect-authenticate.exp drives
  #      `openconnect --authenticate` and writes the resulting session
  #      cookie to this user's own runtime dir (never to argv, never to a
  #      log).
  #   2. Root, on demand: `systemctl start openconnect-luc@<uid>.service`
  #      (polkit-authorized for exactly this user and this unit -- see
  #      openconnect-luc-polkit.js) reads that cookie and makes the tunnel.
  #
  # Built to be called from another program (a Go TUI, a script):
  #   - no controlling tty needed; expect makes its own pty for openconnect
  #   - portal password comes from the keyring (or $GP_PASSWORD)
  #   - MFA code comes from argv[0], $GP_MFA_CODE, or one line of stdin
  #     printed after the "GP_STATUS: mfa-required" marker
  #   - progress is emitted as "GP_STATUS: <state>" lines on stdout;
  #     raw client chatter goes to stderr.
  #   - exit: 0 connected | 2 auth-failed/password-rejected/mfa-failed/
  #           unexpected-exit | 3 no-password
  #           | 4 timeout/needs-attention | 5 mfa not supplied
  vpnConnect = pkgs.writeShellApplication {
    name = "coel-vpn-connect";
    runtimeInputs = [
      pkgs.expect
      pkgs.libsecret
      pkgs.oath-toolkit
      pkgs.systemd
      pkgs.gnugrep
      pkgs.coreutils
      vpnStatus
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        cat >&2 <<'EOF'
      coel-vpn-connect [MFA_CODE]

        Connects the LUC GlobalProtect VPN (via openconnect). Portal password
        is read from the login keyring (store it once with
        coel-vpn-set-password).

        MFA code sources, in order of precedence:
          1. MFA_CODE argument
          2. $GP_MFA_CODE
          3. a TOTP code generated from a seed in the keyring, if one was
             stored with coel-vpn-set-mfa-secret
          4. a single line on stdin, read after this prints:  GP_STATUS: mfa-required

        Override: $GP_PASSWORD (skip the keyring lookup)

        stdout: "GP_STATUS: <state>" lines   stderr: raw client output
        states: connecting mfa-required mfa-rejected authenticated connected
                password-rejected mfa-failed auth-failed unexpected-exit
                no-password mfa-timeout needs-attention timeout
        exit:   0 connected | 2 auth-failed/password-rejected/mfa-failed/
                unexpected-exit | 3 no-password
                4 timeout/needs-attention | 5 mfa not supplied
      EOF
        exit 0
      fi

      # No-op if already up so a stale UI state can't kick off a pointless
      # (lockout-risking) login.
      if coel-vpn-status 2>/dev/null | grep -q '^connected'; then
        echo "GP_STATUS: connected"
        exit 0
      fi

      uid=$(id -u)
      unit="openconnect-luc@$uid.service"

      export GP_PORTAL=${portal}
      export GP_USERNAME=${username}
      export GP_SESSION_FILE="''${XDG_RUNTIME_DIR:-/run/user/$uid}/coel-openconnect-luc-session"

      if [ -z "''${GP_PASSWORD:-}" ]; then
        if GP_PASSWORD=$(secret-tool lookup service ${secretService} account '${secretAccount}' 2>/dev/null) \
           && [ -n "$GP_PASSWORD" ]; then
          export GP_PASSWORD
        else
          echo "GP_STATUS: no-password"
          echo "coel-vpn-connect: no password in keyring -- run 'coel-vpn-set-password' or set GP_PASSWORD." >&2
          exit 3
        fi
      fi

      # Auto-generate the MFA code from a stored TOTP seed, if one exists.
      # Skipped entirely if a code was already given (argv/$GP_MFA_CODE) --
      # those still take precedence inside the expect script regardless,
      # this just avoids a pointless keyring hit when they're already set.
      if [ -z "''${GP_MFA_CODE:-}" ] && [ -z "''${1:-}" ]; then
        if mfa_secret=$(secret-tool lookup service ${mfaSecretService} account '${secretAccount}' 2>/dev/null) \
           && [ -n "$mfa_secret" ]; then
          if GP_MFA_CODE=$(oathtool --totp -b "$mfa_secret" 2>/dev/null) && [ -n "$GP_MFA_CODE" ]; then
            export GP_MFA_CODE
          else
            echo "coel-vpn-connect: stored MFA seed produced no code (check system clock?); falling back to interactive MFA" >&2
          fi
        fi
      fi

      expect -f ${./globalprotect/openconnect-authenticate.exp} "$@"

      if ! systemctl start "$unit"; then
        echo "coel-vpn-connect: failed to start $unit -- see: journalctl -u $unit" >&2
        echo "GP_STATUS: unexpected-exit"
        exit 2
      fi

      for _ in 1 2 3 4 5 6 7 8; do
        sleep 1
        state=$(systemctl is-active "$unit" 2>/dev/null || true)
        if [ "$state" = "failed" ]; then
          echo "coel-vpn-connect: $unit failed -- see: journalctl -u $unit" >&2
          echo "GP_STATUS: unexpected-exit"
          exit 2
        fi
        if coel-vpn-status 2>/dev/null | grep -q '^connected'; then
          echo "GP_STATUS: connected"
          exit 0
        fi
      done

      echo "coel-vpn-connect: tunnel did not come up within 8s of $unit starting" >&2
      echo "GP_STATUS: timeout"
      exit 4
    '';
  };

  # One-time helper: stash the LUC portal password in the login keyring so
  # coel-vpn-connect can read it. Re-run to update it (e.g. after a password
  # change). Neither this nor the Nix store ever holds the secret.
  vpnSetPassword = pkgs.writeShellApplication {
    name = "coel-vpn-set-password";
    runtimeInputs = [ pkgs.libsecret ];
    text = ''
      printf 'LUC portal password for %s: ' '${secretAccount}' >&2
      read -rs pw; echo >&2
      [ -n "$pw" ] || { echo 'empty -- aborting, nothing changed' >&2; exit 1; }
      printf '%s' "$pw" | secret-tool store --label='${secretLabel}' \
        service ${secretService} account '${secretAccount}'
      echo "stored in keyring (service=${secretService} account=${secretAccount})" >&2
    '';
  };

  # Remove the stored password from the keyring.
  vpnForgetPassword = pkgs.writeShellApplication {
    name = "coel-vpn-forget-password";
    runtimeInputs = [ pkgs.libsecret ];
    text = ''
      secret-tool clear service ${secretService} account '${secretAccount}'
      echo "cleared keyring entry (service=${secretService} account=${secretAccount})" >&2
    '';
  };

  # One-time helper: stash the TOTP seed for the MFA prompt, so
  # coel-vpn-connect can generate codes itself instead of prompting a human.
  # This is the raw secret key Microsoft's enrollment flow shows once under
  # "I can't scan the barcode" -- not the QR code image itself, and not a
  # 6-digit code (those expire in seconds; the seed doesn't). Validated by
  # actually generating a code before storing, so a mistyped secret is
  # caught here rather than at connect time.
  vpnSetMfaSecret = pkgs.writeShellApplication {
    name = "coel-vpn-set-mfa-secret";
    runtimeInputs = [ pkgs.libsecret pkgs.oath-toolkit ];
    text = ''
      printf 'TOTP secret key for %s (from the MFA enrollment page): ' '${secretAccount}' >&2
      read -rs raw; echo >&2
      # Microsoft shows it in space-separated groups; strip all whitespace.
      secret=$(printf '%s' "$raw" | tr -d '[:space:]')
      [ -n "$secret" ] || { echo 'empty -- aborting, nothing changed' >&2; exit 1; }

      if ! code=$(oathtool --totp -b "$secret" 2>&1); then
        echo "coel-vpn-set-mfa-secret: that didn't produce a valid code ($code) -- not storing it" >&2
        exit 1
      fi
      echo "generated a test code ($code) -- if that doesn't match your app right now, double-check the secret before trusting this" >&2

      printf '%s' "$secret" | secret-tool store --label='${mfaSecretLabel}' \
        service ${mfaSecretService} account '${secretAccount}'
      echo "stored in keyring (service=${mfaSecretService} account=${secretAccount})" >&2
    '';
  };

  # Remove the stored MFA seed from the keyring (back to interactive MFA).
  vpnForgetMfaSecret = pkgs.writeShellApplication {
    name = "coel-vpn-forget-mfa-secret";
    runtimeInputs = [ pkgs.libsecret ];
    text = ''
      secret-tool clear service ${mfaSecretService} account '${secretAccount}'
      echo "cleared keyring entry (service=${mfaSecretService} account=${secretAccount})" >&2
    '';
  };

  # Machine-readable status probe for the TUI / panel to poll. Prints one
  # token on stdout:
  #   connected | connecting | disconnecting | disconnected | unknown
  # Exit 0 iff connected.
  #
  # Ground truth (the gpd0 tunnel interface having an address) is checked
  # first and wins outright -- unlike the vendor client's unreliable banner
  # text, openconnect-luc@.service's own systemctl state is only consulted
  # as a fallback for the brief windows around startup/teardown when the
  # interface doesn't yet (or no longer) reflect it. There is no
  # "connected-internal" equivalent here (that distinction came from the
  # vendor agent's own banner text, not from anything openconnect reports)
  # and no persistent agent to be "down" -- the service only exists while a
  # tunnel is up or coming up.
  vpnStatus = pkgs.writeShellApplication {
    name = "coel-vpn-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.iproute2
      pkgs.systemd
    ];
    text = ''
      if ip -br addr show dev gpd0 2>/dev/null | grep -q -E 'UP|UNKNOWN.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        echo connected; exit 0
      fi

      unit="openconnect-luc@$(id -u).service"
      state=$(systemctl is-active "$unit" 2>/dev/null || true)
      echo "coel-vpn-status: $unit is $state" >&2

      case "$state" in
        activating)   echo connecting;    exit 1 ;;
        deactivating) echo disconnecting; exit 1 ;;
        active)       echo connecting;    exit 1 ;; # up per systemd, interface not there yet/anymore
        *)            echo disconnected;  exit 1 ;;
      esac
    '';
  };

  # Disconnect is already non-interactive: stopping the unit tears the
  # tunnel down (SIGTERM to the whole cgroup, so openconnect itself exits
  # cleanly); authorized by the same polkit rule as the start in
  # coel-vpn-connect (openconnect-luc-polkit.js).
  vpnDisconnect = pkgs.writeShellApplication {
    name = "coel-vpn-disconnect";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      systemctl stop "openconnect-luc@$(id -u).service" >&2 || true
      echo "GP_STATUS: disconnected"
    '';
  };

in
{
  home.packages = [
    vpnConnect
    vpnSetPassword
    vpnForgetPassword
    vpnSetMfaSecret
    vpnForgetMfaSecret
    vpnStatus
    vpnDisconnect
  ];
}
