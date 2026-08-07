{ config, pkgs, ... }:

{
  programs.micro = {
    enable = true;
    package = pkgs.micro.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        if [ -f $out/share/applications/micro.desktop ]; then
          substituteInPlace $out/share/applications/micro.desktop \
            --replace "Terminal=true" "Terminal=false" \
            --replace "Exec=micro" "Exec=ghostty -e micro"
        fi
      '';
    });

    settings = {
      autosave = true;
      tabsize = 2;
    };
  };

	xdg.configFile."micro/bindings.json" = {
  	force = true;
  	text = ''
			{
			  "Alt-z": "lua:initlua.toggleWordWrap",
			  "CtrlShiftUp": "SpawnMultiCursorUp",
			  "CtrlShiftDown": "SpawnMultiCursorDown",
			  "\u001b[108;6u": "lua:initlua.selectAllOccurrences",
			  "\u001b[3;5~": "DeleteWordRight",
			  "OldBackspace": "DeleteWordLeft",
			  "Ctrl-f": "Find",
			  "Ctrl-n": "FindNext",
			  "Ctrl-p": "FindPrevious"
			}
	  '';
	};
	
	xdg.configFile."micro/init.lua".text = ''
		local micro = import("micro")
		local config = import("micro/config")

		function toggleWordWrap(bp)
		    local curVal = config.GetGlobalOption("wordwrap")
		    if curVal == nil then
		        curVal = false
		    end
		    config.SetGlobalOptionNative("wordwrap", not curVal)
		    config.SetGlobalOptionNative("softwrap", not curVal)
		    return true
		end

		function selectAllOccurrences(bp)
		    local count = 0
		    while bp:SpawnMultiCursor() and count < 1000 do
		        count = count + 1
		    end
		    return true
		end
	'';
}
