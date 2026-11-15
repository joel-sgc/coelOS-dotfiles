{ pkgs, lib, ... }:

let
  mountPoint = "%h/server";
  fusermount = "/run/wrappers/bin/fusermount3";
in
{
  # Personal server sshfs mount, as a background user service instead of an
  # fstab x-systemd.automount entry. The automount version left an empty
  # "server" autofs directory in $HOME even when the server was down, and
  # anything that stat()ed it (a first terminal prompt) blocked on the
  # mount attempt.
  #
  # Here nothing touches ~/server until the mount really succeeded: the
  # directory is created just before sshfs runs and removed again if sshfs
  # fails or the mount drops. Failures (tailscale/server down) just retry
  # every 30s in the background; the session never waits on it.
  systemd.user.services.server-mount = {
    Unit = {
      Description = "sshfs mount of the personal server (~/server)";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = [
        # Clear any stale/dead mount left behind, then create the dir.
        "-${fusermount} -uz ${mountPoint}"
        "${pkgs.coreutils}/bin/mkdir -p ${mountPoint}"
      ];
      # -f keeps sshfs in the foreground so systemd tracks it; it exits when
      # the connection dies (ServerAlive*), which triggers the restart.
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.sshfs}/bin/sshfs -f sftp@jsgc-server:/upload ${mountPoint}"
        "-o IdentityFile=%h/.ssh/id_ed25519_coelos_server,IdentitiesOnly=yes"
        "-o StrictHostKeyChecking=accept-new,BatchMode=yes"
        "-o ConnectTimeout=10,ServerAliveInterval=15,ServerAliveCountMax=3"
        "-o allow_other,idmap=user"
      ];
      ExecStopPost = [
        "-${fusermount} -uz ${mountPoint}"
        "-${pkgs.coreutils}/bin/rmdir ${mountPoint}"
      ];
      Restart = "always";
      RestartSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
