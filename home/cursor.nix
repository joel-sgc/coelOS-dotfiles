{ pkgs, lib, ... }:

let
  # JepriCreations' "Material Design Dark" pack ships Windows .cur/.ani files.
  # They're converted to an Xcursor theme at build time with win2xcur, then
  # each converted file is symlinked under every X11/CSS cursor name it
  # should answer to (Windows has ~15 roles, toolkits ask for ~60 names).
  src = ../assets/material_design_cursors_dark;

  # windows file (no extension) -> X11 names it provides
  names = {
    pointer = [
      "default"
      "left_ptr"
      "arrow"
      "top_left_arrow"
      "context-menu"
    ];
    link = [
      "pointer"
      "pointing_hand"
      "hand1"
      "hand2"
      "alias"
      "dnd-link"
    ];
    help = [
      "help"
      "question_arrow"
      "whats_this"
      "left_ptr_help"
    ];
    work = [
      "progress"
      "left_ptr_watch"
      "half-busy"
      "08e8e1c95fe2fc01f976f1e063a24ccd"
      "3ecb610c1bf2410f44200f48c40d3599"
    ];
    busy = [
      "wait"
      "watch"
    ];
    cross = [
      "crosshair"
      "cross"
      "tcross"
      "cell"
    ];
    text = [
      "text"
      "xterm"
      "ibeam"
      "vertical-text"
    ];
    handwriting = [ "pencil" ];
    unavailiable = [
      "not-allowed"
      "crossed_circle"
      "no-drop"
      "forbidden"
      "circle"
      "dnd-no-drop"
    ];
    vert = [
      "ns-resize"
      "size_ver"
      "sb_v_double_arrow"
      "v_double_arrow"
      "row-resize"
      "split_v"
      "n-resize"
      "s-resize"
      "top_side"
      "bottom_side"
      "00008160000006810000408080010102"
    ];
    horz = [
      "ew-resize"
      "size_hor"
      "sb_h_double_arrow"
      "h_double_arrow"
      "col-resize"
      "split_h"
      "e-resize"
      "w-resize"
      "left_side"
      "right_side"
      "028006030e0e7ebffc7f7070c0600140"
    ];
    dgn1 = [
      "nwse-resize"
      "size_fdiag"
      "bd_double_arrow"
      "nw-resize"
      "se-resize"
      "top_left_corner"
      "bottom_right_corner"
      "c7088f0f3e6c8088236ef8e1e3e70000"
    ];
    dgn2 = [
      "nesw-resize"
      "size_bdiag"
      "fd_double_arrow"
      "ne-resize"
      "sw-resize"
      "top_right_corner"
      "bottom_left_corner"
      "fcf1c3c7cd4491d801f1e1c78f100000"
    ];
    move = [
      "move"
      "all-scroll"
      "fleur"
      "size_all"
      "grab"
      "grabbing"
      "openhand"
      "closedhand"
      "dnd-move"
      "dnd-none"
    ];
    alternate = [
      "up-arrow"
      "center_ptr"
    ];
  };

  linkCmds = lib.concatStringsSep "\n" (
    lib.concatLists (
      lib.mapAttrsToList (
        file: aliases:
        let
          primary = lib.head aliases;
        in
        [ "cp \$NIX_BUILD_TOP/stage/${file} cursors/${primary}" ]
        ++ map (n: "ln -s ${primary} cursors/${n}") (lib.tail aliases)
      ) names
    )
  );

  materialDark =
    pkgs.runCommand "material-design-cursors-dark" { nativeBuildInputs = [ pkgs.win2xcur ]; }
      ''
        d=$out/share/icons/MaterialDark
        mkdir -p $d/cursors $NIX_BUILD_TOP/stage
        win2xcur ${src}/*.cur ${src}/*.ani -o $NIX_BUILD_TOP/stage
        # The pack's name for it is typo'd ("unavailiable"); account/place are
        # Windows-only "person"/"pin" roles with no X11 equivalent.
        cat > $d/index.theme <<EOF
        [Icon Theme]
        Name=MaterialDark
        Comment=Material Design Dark cursors by JepriCreations
        EOF
        cd $d
        ${linkCmds}
      '';
in
{
  home.pointerCursor = {
    package = materialDark;
    name = "MaterialDark";
    size = 32; # source art is 32x32 only; larger sizes get upscaled
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = false;
  };
}
