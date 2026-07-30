{ config, pkgs, ... }:

{
  programs.micro = {
    enable = true;

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
