{ config, pkgs, ... }:

{
	programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https"; # Tells gh to use HTTPS instead of SSH
    };
  };

  programs.git = {
    enable = true;
		userName = "joel-sgc";
		userEmail = "joeloultook@gmail.com";
    
    extraConfig = {
      # This tells Git to use the GitHub CLI to authenticate your pushes
      credential.helper = "${pkgs.gh}/bin/gh auth git-credential";
    };
  };
 }
