{ inputs, pkgs, ... }:

let
  theme = import ./theme/onedark.nix;

  # Fresh's theme schema is coarser than VS Code's: exactly 11 syntax.*
  # categories (fresh-editor's SyntaxColors struct), no function-call-vs-
  # declaration split, no dedicated JSX tag category -- Variable+Property
  # and Constant+Number+Attribute are each folded into one bucket. Lands
  # fine for tal7aouy's palette since the folded roles share colors anyway,
  # but it's a real ceiling: e.g. no way to color `=>`/`===` differently
  # from `+`/`-`, every operator shares one `syntax.operator` key.
  hex = c: builtins.substring 1 6 c;
  toRgb =
    c:
    let
      h = hex c;
      r = builtins.substring 0 2 h;
      g = builtins.substring 2 2 h;
      b = builtins.substring 4 2 h;
    in
    [
      (builtins.fromTOML "x=0x${r}").x
      (builtins.fromTOML "x=0x${g}").x
      (builtins.fromTOML "x=0x${b}").x
    ];

  bracketCycle = [
    (toRgb "#d19a66")
    (toRgb "#c678dd")
    (toRgb "#56b6c2")
    (toRgb "#d19a66")
    (toRgb "#c678dd")
    (toRgb "#56b6c2")
  ];
in
{
  home.packages = [ inputs.fresh.packages.${pkgs.stdenv.hostPlatform.system}.default ];

  xdg.configFile."fresh/config.json".text = builtins.toJSON {
    theme = "onedark-tal7aouy.json";
    # "vscode" is a small overlay on the already VS Code-like "default",
    # adding Ctrl+D multi-cursor, Ctrl+/ comment toggle, Ctrl+Shift+K delete
    # line, Ctrl+G goto line -- strict superset, no reason not to take it.
    keymap = "vscode";
    editor = {
      # Already the default -- set explicitly so it's not silently
      # dependent on that staying true.
      line_wrap = true;
      # Carried over from the old micro setup (home/micro.nix had
      # tabsize = 2) -- Fresh's own default is 4.
      tab_size = 2;
      # Same intent as micro's `autosave = true`; Fresh's mechanism is a
      # periodic timer rather than save-on-every-edit, so this also pairs
      # with a shorter interval than the 30s default.
      auto_save_enabled = true;
      auto_save_interval_secs = 5;
    };
    # The built-in typescript/javascript LSP entries already have the right
    # command but `"auto_start": false` -- that's why the status bar showed
    # "LSP (off)", not a missing server. The `lsp` map deep-merges
    # per-field, so this only needs to override that one field.
    #
    # QML isn't a built-in language, so it needs both a `languages`
    # registration (extensions/comments/indent) and a full `lsp` entry, not
    # just an override. `grammar` left unset: QML isn't among fresh's
    # bundled tree-sitter grammars, so indent-rules-only is the best
    # available here. `qmlls` (home/quickshell.nix) takes no `--stdio`
    # flag -- stdio is its only communication mode.
    languages.qml = {
      extensions = [ "qml" ];
      comment_prefix = "//";
      auto_indent = true;
    };
    lsp = {
      typescript.auto_start = true;
      javascript.auto_start = true;
      qml = {
        command = "qmlls";
        args = [ ];
        enabled = true;
      };
    };
    # Layers on top of the resolved `keymap` above as overrides -- none of
    # these three exist in "vscode" by default (Ctrl+W is bound to
    # `select_word` there; Ctrl+Tab/Ctrl+Shift+Tab are unbound). Ghostty's
    # own ctrl+w/ctrl+tab/ctrl+shift+tab bindings are unbound in
    # home/ghostty.nix so these reach Fresh instead of Ghostty intercepting
    # them first.
    keybindings = [
      {
        key = "w";
        modifiers = [ "ctrl" ];
        action = "close_tab";
        args = { };
        when = "normal";
      }
      {
        key = "Tab";
        modifiers = [ "ctrl" ];
        action = "next_buffer";
        args = { };
        when = "normal";
      }
      {
        key = "Tab";
        modifiers = [
          "ctrl"
          "shift"
        ];
        action = "prev_buffer";
        args = { };
        when = "normal";
      }
    ];
  };

  xdg.configFile."fresh/themes/onedark-tal7aouy.json".text = builtins.toJSON {
    name = "onedark-tal7aouy";
    extends = "builtin://dark";

    editor = {
      bg = toRgb theme.bg;
      fg = toRgb theme.fg;
      cursor = toRgb theme.blue;
      selection_bg = toRgb theme.surface;
      current_line_bg = toRgb theme.surface;
      line_number_fg = toRgb theme.comment;
      line_number_bg = toRgb theme.bg;
      bracket_match_fg = toRgb theme.purple;
      bracket_rainbow_1 = builtins.elemAt bracketCycle 0;
      bracket_rainbow_2 = builtins.elemAt bracketCycle 1;
      bracket_rainbow_3 = builtins.elemAt bracketCycle 2;
      bracket_rainbow_4 = builtins.elemAt bracketCycle 3;
      bracket_rainbow_5 = builtins.elemAt bracketCycle 4;
      bracket_rainbow_6 = builtins.elemAt bracketCycle 5;
      indent_rainbow_1 = builtins.elemAt bracketCycle 0;
      indent_rainbow_2 = builtins.elemAt bracketCycle 1;
      indent_rainbow_3 = builtins.elemAt bracketCycle 2;
      indent_rainbow_4 = builtins.elemAt bracketCycle 3;
      indent_rainbow_5 = builtins.elemAt bracketCycle 4;
      indent_rainbow_6 = builtins.elemAt bracketCycle 5;
    };

    diagnostic = {
      error_fg = toRgb theme.error;
      warning_fg = toRgb theme.yellow;
      info_fg = toRgb theme.blue;
    };

    syntax = {
      # scope "keyword"/"keyword.control" -> #d55fde
      keyword = toRgb theme.purple;
      # scope "string" -> #89ca78
      string = toRgb theme.green;
      comment = toRgb theme.comment;
      # scope "entity.name.function"/"meta.function-call" -> #61afef
      function = toRgb theme.blue;
      # scope "entity.name.type"/"support.class" -> #e5c07b
      type = toRgb theme.yellow;
      # scope "variable.other.readwrite" -> #ef596f -- also catches
      # entity.name.tag (JSX tags) via Fresh's Variable+Property merge.
      variable = toRgb theme.red;
      variable_builtin = toRgb theme.purple;
      # scope "constant"/"constant.numeric" -> #d19a66 -- also catches JSX
      # attribute names via Fresh's Constant+Number+Attribute merge.
      constant = toRgb theme.orange;
      # scope "keyword.operator" (generic default) -> #abb2bf. Real theme
      # colors specific operators differently elsewhere on this desktop,
      # but Fresh has one operator category for everything.
      operator = toRgb theme.fg;
      punctuation_bracket = toRgb theme.fg;
      punctuation_delimiter = toRgb theme.fg;
    };
  };
}
