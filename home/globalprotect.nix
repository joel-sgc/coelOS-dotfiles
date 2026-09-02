{ config, pkgs, lib, ... }:

let
  gpFHS = (import ../lib/globalprotect-fhs.nix { inherit pkgs; }) "globalprotect-agent-fhs";

  portal = "secureaccess.luc.edu";
  username = "jgutierrez11@luc.edu";

  # Secret Service (libsecret / `secret-tool`) attributes for the stored LUC
  # portal password. On this box org.freedesktop.secrets is owned by
  # gnome-keyring (PAM-unlocked at login) -- kwallet-query's --write-password
  # silently no-ops here, so we go through libsecret instead. The lookup key
  # is the (service, account) pair below.
  secretService = "coel-vpn";
  secretAccount = username;
  secretLabel = "LUC GlobalProtect";

  # Driven wrapper around the vendor `globalprotect connect`. LUC auth is
  # plain username+password against the portal (no SAML) followed by a
  # gateway OTP challenge -- see globalprotect-hip-investigation.md and
  # home/globalprotect/gp-connect.exp for the reverse-engineered flow.
  #
  # Built to be called from another program (a Go TUI, a script):
  #   - no controlling tty needed; expect makes its own pty for the CLI
  #   - portal password comes from the keyring (or $GP_PASSWORD)
  #   - MFA code comes from argv[0], $GP_MFA_CODE, or one line of stdin
  #     printed after the "GP_STATUS: mfa-required" marker
  #   - progress is emitted as "GP_STATUS: <state>" lines on stdout;
  #     raw client chatter goes to stderr
  #   - exit: 0 connected | 2 auth-failed | 3 no-password
  #           | 4 timeout/needs-attention | 5 mfa not supplied
  vpnConnect = pkgs.writeShellApplication {
    name = "coel-vpn-connect";
    runtimeInputs = [ gpFHS pkgs.expect pkgs.libsecret ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        cat >&2 <<'EOF'
      coel-vpn-connect [MFA_CODE]

        Connects the LUC GlobalProtect VPN. Portal password is read from the
        login keyring (store it once with coel-vpn-set-password).

        MFA code sources, in order of precedence:
          1. MFA_CODE argument
          2. $GP_MFA_CODE
          3. a single line on stdin, read after this prints:  GP_STATUS: mfa-required

        Override: $GP_PASSWORD (skip the keyring lookup)

        stdout: "GP_STATUS: <state>" lines   stderr: raw client output
        exit:   0 connected | 2 auth-failed | 3 no-password
                4 timeout/needs-attention | 5 mfa not supplied
      EOF
        exit 0
      fi

      export GP_PORTAL=${portal}
      export GP_USERNAME=${username}
      export GP_FHS_CMD=globalprotect-agent-fhs

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

      exec expect -f ${./globalprotect/gp-connect.exp} "$@"
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

  # Machine-readable status probe for the TUI to poll. Prints one token on
  # stdout: connected | connected-internal | disconnected | unknown.
  # Exit 0 iff connected (either flavour).
  vpnStatus = pkgs.writeShellApplication {
    name = "coel-vpn-status";
    runtimeInputs = [ gpFHS ];
    text = ''
      out=$(globalprotect-agent-fhs -c 'cd /opt/paloaltonetworks/globalprotect && ./globalprotect show --status' 2>/dev/null || true)
      case "$out" in
        *"Connected - Internal"*) echo connected-internal; exit 0 ;;
        *"Connected"*)            echo connected;          exit 0 ;;
        *"Disconnected"*)         echo disconnected;       exit 1 ;;
        *)                        echo unknown;            exit 1 ;;
      esac
    '';
  };

  # Disconnect is already non-interactive. Uses the system daemon's FHS
  # wrapper (globalprotect-fhs, from modules/globalprotect.nix -- on PATH
  # via environment.systemPackages there), not the agent's.
  vpnDisconnect = pkgs.writeShellApplication {
    name = "coel-vpn-disconnect";
    text = ''
      globalprotect-fhs -c 'cd /opt/paloaltonetworks/globalprotect && ./globalprotect disconnect' >&2 || true
      echo "GP_STATUS: disconnected"
    '';
  };
in
{
  # Exposes `globalprotect-agent-fhs` on PATH so the vendor `globalprotect`
  # CLI (connect/disconnect/show --status) can be run by hand -- it was
  # previously only reachable via its full store path inside the systemd
  # service below.
  home.packages = [
    gpFHS
    vpnConnect
    vpnSetPassword
    vpnForgetPassword
    vpnStatus
    vpnDisconnect
  ];

  systemd.user.services.globalprotect-agent = {
    Unit.Description = "GlobalProtect VPN client Agent";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${gpFHS}/bin/globalprotect-agent-fhs -c 'cd /opt/paloaltonetworks/globalprotect && ./PanGPA start'";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };
}
