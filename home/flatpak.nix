{ config, pkgs, inputs, ... }:

{
  services.flatpak = {
    enable = true;
    
    # Automatically update flatpaks when you rebuild your system
    update.onActivation = true; 
    
    packages = [
      "org.vinegarhq.Sober"
    ];
  };
}
