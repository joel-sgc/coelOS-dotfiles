{ pkgs, lib, config, ... }:

let
  fusermount = "/run/wrappers/bin/fusermount3";
  # The server is mounted in the (RAM-backed) runtime directory, and ~/server is only a
  # symlink to it. When the server is down nothing exists at the mount point, so ~/server
  # is a dangling link: nothing can be saved, created or "mkdir -p"-ed through it, and no
  # ghost copy of the folder can build up on the real disk. (Before, ~/server was a real
  # directory, and anything written to it while the mount was down -- an app saving to its
  # remembered path -- stayed behind on disk, hidden again by the next mount.)
  uid = "1000";
  mountPoint = "/run/user/${uid}/server";

  # Remove whatever is left at the mount point when no mount is there: a stray directory,
  # or files something managed to write during the few seconds a connect attempt takes.
  # It only ever touches the runtime (RAM) directory, and only when `mountpoint` says
  # for sure that nothing is mounted (exit status 32 means "not a mount point"; a timeout or
  # any other result, such as on a dead mount, leaves everything alone).
  cleanMountPoint = pkgs.writeShellScript "server-mount-clean" ''
    m="$XDG_RUNTIME_DIR/server"
    ${fusermount} -uz "$m" 2>/dev/null
    ${pkgs.coreutils}/bin/timeout 5 ${pkgs.util-linux}/bin/mountpoint -q "$m" 2>/dev/null
    if [ $? -eq 32 ]; then
      ${pkgs.findutils}/bin/find "$m" -mindepth 1 -delete 2>/dev/null
      ${pkgs.coreutils}/bin/rmdir "$m" 2>/dev/null
    fi
    exit 0
  '';
in
{
  home.file."server".source = config.lib.file.mkOutOfStoreSymlink mountPoint;

  # One-off migration: ~/server used to be a real directory. A symlink cannot replace a
  # directory, so any old directory is moved aside first (never deleted): a still-live mount
  # is let go, an empty directory is removed, and one with files in it -- the ghost copy --
  # becomes ~/server.offline-copy for you to look through (it may hold files that exist
  # nowhere else, saved while the server was unreachable).
  home.activation.serverMountMigrate = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    d="$HOME/server"
    ${fusermount} -uz "$d" 2>/dev/null || true
    if [ -d "$d" ] && [ ! -L "$d" ]; then
      if ! $DRY_RUN_CMD ${pkgs.coreutils}/bin/rmdir "$d" 2>/dev/null; then
        dest="$HOME/server.offline-copy"
        [ -e "$dest" ] && dest="$dest.$(date +%Y%m%d-%H%M%S)"
        echo "server-mount: moving the old ~/server directory (it has files in it) to $dest"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$d" "$dest"
      fi
    fi
  '';

  # Personal server sshfs mount, as a background user service instead of an
  # fstab x-systemd.automount entry (that version left an empty "server" autofs
  # directory in $HOME even when the server was down, and anything that stat()ed it
  # blocked on the mount attempt).
  #
  # Failures (tailscale/server down) just retry every 30s in the background; the
  # session never waits on it.
  systemd.user.services.server-mount = {
    Unit = {
      Description = "sshfs mount of the personal server (~/server)";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = [
        # Clear any stale/dead mount and stray files, then make the mount point.
        "${cleanMountPoint}"
        "${pkgs.coreutils}/bin/mkdir -p %t/server"
      ];
      # -f keeps sshfs in the foreground so systemd tracks it; it exits when
      # the connection dies (ServerAlive*), which triggers the restart.
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.sshfs}/bin/sshfs -f sftp@jsgc-server:/upload %t/server"
        "-o IdentityFile=%h/.ssh/id_ed25519_coelos_server,IdentitiesOnly=yes"
        "-o StrictHostKeyChecking=accept-new,BatchMode=yes"
        "-o ConnectTimeout=10,ServerAliveInterval=15,ServerAliveCountMax=3"
        "-o allow_other,idmap=user"
      ];
      ExecStopPost = [ "${cleanMountPoint}" ];
      Restart = "always";
      RestartSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
