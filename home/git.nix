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
    settings = {
      credential.helper = "${pkgs.gh}/bin/gh auth git-credential";
    	user = {
    		name = "joel-sgc";
    		email = "joeloultook@gmail.com";
    	};
    };    
  };
 }
