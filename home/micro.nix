{ pkgs, ... }:

let
  # Real LSP client for micro (AndCake/micro-plugin-lsp) -- diagnostics,
  # hover, completion, go-to-definition, backed by actual language servers,
  # instead of micro's bundled `linter` plugin (which just shells out to
  # external linters and can't do any of that). This is what was missing
  # before and is the thing that actually gets closer to VS Code-level
  # tooling within what micro can support.
  #
  # Vendored via fetchFromGitHub rather than micro's own `-plugin install`
  # (which fetches at runtime, non-reproducible) -- this places the exact
  # same files that command would, just declaratively.
  lspPlugin = pkgs.fetchFromGitHub {
    owner = "AndCake";
    repo = "micro-plugin-lsp";
    rev = "v0.6.3";
    hash = "sha256-rZ9Vw9WPGNaJBGHKU40F6cBIYQ1JFtSKPDrheazKkPY=";
  };

  theme = import ./theme/onedark.nix;
in
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
      # Hand-rolled, not micro's bundled "one-dark" (runtime/colorschemes/
      # one-dark.micro) -- checked its actual source and it's the canonical
      # Atom values (#21252C bg, #C678DD purple, #98C379 green), not
      # tal7aouy's tweaked ones (home/theme/onedark.nix). Same gap as
      # ghostty's bundled "Atom One Dark". Built below from the bundled
      # one's own role structure, substituting our verified palette.
      colorscheme = "onedark-tal7aouy";

      # nix=nixd matches the language server already installed system-wide
      # (configuration.nix, for VS Code's nix-ide). The rest are installed
      # below specifically for this. Extend the same way for any other
      # language -- filetype=command, comma-separated.
      "lsp.server" = "nix=nixd,python=pylsp,go=gopls,rust=rust-analyzer,lua=lua-language-server,bash=bash-language-server start,typescript=typescript-language-server --stdio,javascript=typescript-language-server --stdio";
      "lsp.formatOnSave" = false;
    };
  };

  xdg.configFile."micro/plug/lsp".source = lspPlugin;

  # Role structure mirrors micro's own bundled one-dark.micro (see comment
  # on `colorscheme` above), just re-pointed at the verified tal7aouy values.
  xdg.configFile."micro/colorschemes/onedark-tal7aouy.micro".text = ''
    color-link default "${theme.fg},${theme.bg}"
    color-link color-column "${theme.surface}"
    color-link comment "${theme.comment}"
    color-link constant "${theme.purple}"
    color-link constant.number "${theme.yellow}"
    color-link constant.string "${theme.green}"
    color-link constant.string.char "${theme.green}"
    color-link constant.specialChar "${theme.yellow}"
    color-link current-line-number "${theme.fg},${theme.bg}"
    color-link cursor-line "${theme.surface}"
    color-link divider "${theme.fg}"
    color-link error "${theme.error}"
    color-link diff-added "${theme.green}"
    color-link diff-modified "${theme.yellow}"
    color-link diff-deleted "${theme.error}"
    color-link gutter-error "${theme.error}"
    color-link gutter-warning "${theme.yellow}"
    color-link hlsearch "${theme.bg},${theme.yellow}"
    color-link identifier "${theme.blue}"
    color-link identifier.class "${theme.purple}"
    color-link identifier.var "${theme.purple}"
    color-link indent-char "${theme.comment}"
    color-link line-number "${theme.comment},${theme.bg}"
    color-link preproc "${theme.orange}"
    color-link special "${theme.orange}"
    color-link statement "${theme.purple}"
    color-link statusline "${theme.bg},${theme.fg}"
    color-link symbol "${theme.orange}"
    color-link symbol.brackets "${theme.fg}"
    color-link symbol.operator "${theme.purple}"
    color-link symbol.tag "${theme.orange}"
    color-link tabbar "${theme.fg},${theme.surface}"
    color-link todo "${theme.comment}"
    color-link type "${theme.cyan}"
    color-link type.keyword "${theme.purple}"
    color-link underlined "${theme.blue}"
    color-link match-brace "${theme.bg},${theme.purple}"
    color-link tab-error "${theme.error}"
    color-link trailingws "${theme.error}"
  '';

  # Extends micro's bundled runtime/syntax/typescript.yaml (same filetype
  # declaration + detect regex overrides it, per micro's own docs) with
  # coverage the stock ruleset lacks for a JSX-heavy codebase: JSX/TSX tag
  # names, decorators, and a few TS keywords added after the bundled file's
  # last update (satisfies, keyof, readonly, infer, unique, override, out).
  # Also fixes a real bug in the stock `identifier` rule: it only matched a
  # bare `name(`, so any generic-parameterized call like `useMemo<T>(...)`
  # never got identifier coloring while plain `useState()` did.
  xdg.configFile."micro/syntax/typescript.yaml".text = ''
    filetype: typescript

    detect:
        filename: "\\.tsx?$"

    rules:
        - constant.number: "\\b[-+]?([1-9][0-9]*|0[0-7]*|0x[0-9a-fA-F]+)([uU][lL]?|[lL][uU]?)?\\b"
        - constant.number: "\\b[-+]?([0-9]+\\.[0-9]*|[0-9]*\\.[0-9]+)([EePp][+-]?[0-9]+)?[fFlL]?"
        - constant.number: "\\b[-+]?([0-9]+[EePp][+-]?[0-9]+)[fFlL]?"
        - statement: "\\b(abstract|as|async|await|break|case|catch|class|const|constructor|continue)\\b"
        - statement: "\\b(debugger|declare|default|delete|do|else|enum|export|extends|finally|for|from)\\b"
        - statement: "\\b(function|get|if|implements|import|in|instanceof|interface|is|let|module|namespace)\\b"
        - statement: "\\b(new|of|out|override|package|private|protected|public|require|return|set|static|super|switch)\\b"
        - statement: "\\b(satisfies|this|throw|try|type|typeof|var|void|while|with|yield)\\b"
        - type.keyword: "\\b(infer|keyof|readonly|unique)\\b"
        - constant: "\\b(false|true|null|undefined|NaN)\\b"
        - type: "\\b(Array|Boolean|Date|Enumerator|Error|Function|Math)\\b"
        - type: "\\b(Number|Object|RegExp|String|Symbol)\\b"
        - type: "\\b(any|unknown|boolean|never|number|string|symbol)\\b"
        - statement: "[-+/*=<>!~%?:&|]"
        # Decorators (@Component, @Injectable, ...).
        - special: "@[A-Za-z_][A-Za-z0-9_.]*"
        # JSX/TSX tag names. Inherently ambiguous with a spaceless "a<B"
        # comparison since a regex-based highlighter has no real parser to
        # disambiguate, but JSX is overwhelmingly the more common case in a
        # React codebase, so it's placed after the operator rule above to
        # win that tradeoff for the shared "<"/">" characters.
        - symbol.tag: "</?[A-Za-z][A-Za-z0-9_.]*"
        # Identifier calls, including generic-parameterized ones
        # (useMemo<T>(...), useState<T>(...) -- the bundled rule only
        # matched a bare "name(", missing every generic-typed hook/call).
        # Placed after the JSX tag rule above (later wins on overlap) so a
        # full "name<Type>(" call reclaims the "<Type" span the JSX rule
        # would otherwise also match, while genuine JSX tags (never
        # followed by "(") are untouched by this rule either way.
        - identifier: "[A-Za-z_][A-Za-z0-9_]*(<[^<>]*>)?[[:space:]]*[(]"
        - constant: "/[^*]([^/]|(\\\\/))*[^\\\\]/[gim]*"
        - constant: "\\\\[0-7][0-7]?[0-7]?|\\\\x[0-9a-fA-F]+|\\\\[bfnrt'\"\\?\\\\]"
        - comment:
            start: "//"
            end: "$"
            rules: []
        - comment:
            start: "/\\*"
            end: "\\*/"
            rules:
                - todo: "TODO:?"
        - constant.string:
            start: "\""
            end: "\""
            skip: "\\\\."
            rules:
                - constant.specialChar: "\\\\."
        - constant.string:
            start: "'"
            end: "'"
            skip: "\\\\."
            rules:
                - constant.specialChar: "\\\\."
        - constant.string:
            start: "`"
            end: "`"
            rules:
                - constant.specialChar: "\\\\."
                - identifier: "\\x24\\{.*?\\}"
  '';

  home.packages = [
    pkgs.python3Packages.python-lsp-server # pylsp
    pkgs.gopls
    pkgs.rust-analyzer
    pkgs.lua-language-server
    pkgs.bash-language-server
    pkgs.typescript-language-server
  ];

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
