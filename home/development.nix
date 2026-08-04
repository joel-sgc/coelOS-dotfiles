{ config, pkgs, ... }:

{
  programs.nodejs = {
    enable = true;
	};

	programs.pnpm = {
		enable = true;
	};
}
