# Builds the swipe test plugin against a given Hyprland (the patched one).
#   nix build --impure --expr '... import ./plugin.nix { inherit pkgs; hyprland = patched; }'
{ pkgs, hyprland }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  inherit hyprland;
  pluginName = "swipetest";
  version = "0";
  src = ./.;

  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    $CXX -shared -fPIC -std=c++2b -Wno-narrowing -O1 \
      $(pkg-config --cflags hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon) \
      swipetest.cpp -o libswipetest.so
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp libswipetest.so $out/lib/
    runHook postInstall
  '';

  meta = {
    description = "Synthetic trackpad swipes for testing Hyprland's gesture code";
    license = pkgs.lib.licenses.bsd3;
  };
}
