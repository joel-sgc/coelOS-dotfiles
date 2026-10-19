# OPTIONAL, UNTESTED ON HARDWARE.
# After an EC reset (battery drained, EC reboot) the EC boots Framework's RO
# firmware again. This service notices that at boot and jumps back to the
# patched RW firmware, which reboots the laptop once.
#
# The jump is an abrupt power-off, which counts as a strike against the TPM's
# dictionary-attack limit. See "TPM lockout after EC jumps" in the README.
#
# EXPECTED_RW must match the "RW Version" line of `framework_tool --versions`
# for YOUR build. Framework's factory firmware is v3.4.113388, our builds are
# v3.4.113387, so this never jumps into factory RW by mistake.
{ pkgs, ... }:
let
  EXPECTED_RW = "azalea_v3.4.113387";
in
{
  systemd.services.ec-jump-rw = {
    description = "Return the EC to the custom RW firmware after an EC reset";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = [ "display-manager.service" ];
    path = [ pkgs.framework-tool pkgs.gnugrep pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      out=$(framework_tool --versions) || exit 0
      # Already running RW: nothing to do.
      echo "$out" | grep -q "Current image: *RO" || exit 0
      # Only jump if RW still holds our build (a BIOS update would replace it).
      echo "$out" | grep -q "RW Version: *${EXPECTED_RW}" || exit 0
      # Loop guard: jumped in the last 10 minutes and still on RO? Give up.
      stamp=/var/lib/ec-jump-rw/last
      mkdir -p /var/lib/ec-jump-rw
      if [ -f "$stamp" ] && [ $(( $(date +%s) - $(cat "$stamp") )) -lt 600 ]; then
        echo "Jumped recently but EC is still on RO; not retrying." >&2
        exit 1
      fi
      date +%s > "$stamp"
      sync
      framework_tool --reboot-ec jump-rw
    '';
  };
}
