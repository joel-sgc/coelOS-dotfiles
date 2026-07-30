{ ... }:

{
  networking.firewall = rec {
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = allowedTCPPortRanges; # Same range for UDP discovery
  };

	programs.kdeconnect.enable = true;
}
