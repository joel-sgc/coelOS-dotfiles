{ inputs, pkgs, ... }:

let
  theme = import ./theme/onedark.nix;

  # Fresh's theme schema is real but coarser than VS Code's -- verified
  # directly from its Rust source (crates/fresh-editor/src/view/theme/types.rs,
  # SyntaxColors struct): exactly 11 syntax.* categories, no separate
  # function-call-vs-declaration, no dedicated JSX tag category. The
  # scope->category mapping (highlight_engine.rs) folds Variable+Property
  # into one bucket and Constant+Number+Attribute into another. This
  # happens to land fine for tal7aouy's specific palette (its real
  # entity.name.tag and variable.other.readwrite are both #ef596f anyway,
  # and entity.other.attribute-name / constant.numeric are both #d19a66),
  # but it's a real ceiling, not a stylistic choice -- e.g. there's no way
  # to color `=>`/`===` differently from `+`/`-`; every operator shares one
  # `syntax.operator` key.
  #
  # Bracket-pair-by-depth is native here (editor.bracket_rainbow_1..6),
  # unlike Emacs where that needed a separate rainbow-delimiters package.
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
    # "default" is already VS Code-like (per the README), "vscode" is a
    # small overlay on top of it (verified via the real keymap JSON) adding
    # Ctrl+D multi-cursor, Ctrl+/ comment toggle, Ctrl+Shift+K delete line,
    # Ctrl+G goto line -- strict superset, no reason not to take it.
    keymap = "vscode";
    editor = {
      # Already the default (verified via `--cmd config show`) -- set
      # explicitly so it's not silently dependent on that staying true.
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
    # Verified via `--cmd config show`: the built-in typescript/javascript
    # LSP entries already have `"enabled": true` and the right command
    # (typescript-language-server --stdio), but `"auto_start": false` --
    # that's the actual reason the status bar showed "LSP (off)", not a
    # missing server. The `lsp` map deep-merges per-field (confirmed in the
    # docs), so this only needs to override the one field; command/args/
    # root_markers/etc. are preserved from the built-in defaults.
    #
    # QML isn't a built-in language (unlike typescript/javascript above),
    # so it needs both a `languages` registration (basic recognition --
    # extensions/comments/indent) and a full `lsp` entry, not just an
    # override -- see docs/configuration/index.md's "Add a Custom
    # Language" example. `grammar` intentionally left unset: confirmed via
    # `fresh --cmd grammar list` that QML isn't among the 147 bundled
    # tree-sitter grammars, so indent-rules-only is genuinely the best
    # available here, not a placeholder pending a check.
    # `qmlls` (home/quickshell.nix) takes no `--stdio`/mode flag; verified
    # via `qmlls --help` -- stdio is its only communication mode.
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
    # Top-level `keybindings` layers on top of the resolved `keymap` above
    # (confirmed in fresh's source, input/keybindings.rs: the active map's
    # bindings load first, then these are loaded "as overrides") -- these
    # three don't exist in "vscode" at all by default: Ctrl+W is bound to
    # `select_word` there (Fresh's own close-tab default is Alt+W), and
    # Ctrl+Tab/Ctrl+Shift+Tab aren't bound to anything. Ghostty's own
    # ctrl+w/ctrl+tab/ctrl+shift+tab bindings are unbound in home/ghostty.nix
    # so these actually reach Fresh instead of Ghostty intercepting them
    # for its own ctrl+w = close_tab / built-in tab-switching first.
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
      # scope "entity.name.function"/"meta.function-call" -> #61afef --
      # Fresh's own mapping already folds calls and declarations into one
      # Function category, so unlike Emacs this needed no extra work.
      function = toRgb theme.blue;
      # scope "entity.name.type"/"support.class" -> #e5c07b
      type = toRgb theme.yellow;
      # scope "variable.other.readwrite" -> #ef596f -- this bucket also
      # catches entity.name.tag (JSX tags) and property access via Fresh's
      # Variable+Property merge, which happens to match since both are
      # #ef596f in the real theme anyway.
      variable = toRgb theme.red;
      variable_builtin = toRgb theme.purple;
      # scope "constant"/"constant.numeric" -> #d19a66 -- also catches JSX
      # attribute names via Fresh's Constant+Number+Attribute merge, which
      # again happens to match (entity.other.attribute-name is also
      # #d19a66 in the real theme).
      constant = toRgb theme.orange;
      # scope "keyword.operator" (generic default) -> #abb2bf. Real theme
      # colors specific operators differently (=> and === requested purple
      # elsewhere on this desktop), but Fresh has one operator category for
      # everything -- no per-operator override exists in this theme schema.
      operator = toRgb theme.fg;
      punctuation_bracket = toRgb theme.fg;
      punctuation_delimiter = toRgb theme.fg;
    };
  };
}
