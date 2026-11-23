{ ... }:

{
  services.flatpak = {
    enable = true;

    # Automatically update flatpaks when you rebuild your system
    update.onActivation = true;

    packages = [
      "org.vinegarhq.Sober"
      "com.bambulab.BambuStudio"
      "com.orcaslicer.OrcaSlicer"
      "com.modrinth.ModrinthApp"
    ];

    # ~/server is a link to the sshfs mount in /run/user/1000/server (home/server-mount.nix),
    # which the sandbox cannot see unless it is shared: without this the slicers' file
    # pickers show ~/server as an empty/dead link even while it is mounted.
    overrides = {
      "com.bambulab.BambuStudio".Context.filesystems = [ "xdg-run/server" ];
      "com.orcaslicer.OrcaSlicer".Context.filesystems = [ "xdg-run/server" ];
    };
  };
}
