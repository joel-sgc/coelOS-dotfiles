# Policy routing reconciler for the LUC GlobalProtect tunnel -- split out
# from the old modules/globalprotect.nix (vendor client, removed; see
# [[project_globalprotect_luc]]) because this part is backend-agnostic: it
# only cares about a tunnel interface named gpd0 existing, not about who
# created it. The openconnect backend (modules/globalprotect-openconnect.nix)
# keeps that same interface name via --interface=gpd0 specifically so this
# reconciler needed no changes when the backend switched.
{ pkgs, lib, ... }:

let
  # Ranges that must go through GlobalProtect even while Tailscale has an
  # exit node (see globalprotect/vpn-routes.sh for the rule ladder). GP here is
  # a pure full tunnel with no pushed route list, so LUC's networks are
  # declared by hand. 147.126.0.0/16 is LUC's public block (IP-gated library
  # resources etc.); the gateway's own /32 is exempted automatically.
  gpRanges = [ "10.0.0.0/8" "147.126.0.0/16" ];

  vpnRoutes = pkgs.writeShellApplication {
    name = "coel-vpn-routes";
    runtimeInputs = [ pkgs.iproute2 pkgs.jq pkgs.gnugrep pkgs.coreutils ];
    text = "export GP_RANGES=\"${lib.concatStringsSep " " gpRanges}\"\n" + builtins.readFile ./globalprotect/vpn-routes.sh;
  };
in
{
  environment.systemPackages = [ vpnRoutes ];

  # Long-running reconciler: re-applies the rule ladder whenever links,
  # addresses or routes change (gpd0 / tailscale0 / wifi coming and going).
  systemd.services.coel-vpn-routes = {
    description = "Reconcile Tailscale / GlobalProtect / LAN policy routing";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${vpnRoutes}/bin/coel-vpn-routes watch";
      ExecStopPost = "${vpnRoutes}/bin/coel-vpn-routes down";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
