{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    defaultKeymap = "emacs"; # Replaces `bindkey -e`

    # 1. CORE & HISTORY
    history = {
      size = 1000;
      save = 1000;
      path = "${config.home.homeDirectory}/.histfile";
    };

    # 5. ALIASES & UTILITIES
    shellAliases = {
      ls = "eza -l --header";
      grep = "grep --color=auto";
    };

    # Set environment variables here
    sessionVariables = {
      WORDCHARS = "";
      NVM_DIR = "$HOME/.nvm";
    };

    # 3. ZLE WIDGETS & 4. KEYBINDINGS (Injected at the end of .zshrc)
    initContent = ''
      # Initialize NVM
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

      # -----------------------------------------------------------------------------
      # ZLE (Zsh Line Editor) CUSTOM WIDGETS
      # -----------------------------------------------------------------------------
      typeset -g -a zle_highlight
      zle_highlight+=(region:standout)

      # --- Selection & Deletion ---
      .zle_select-all() { MARK=0; CURSOR=$#BUFFER; REGION_ACTIVE=1; }
      zle -N .zle_select-all

      .zle_self_insert() { (( REGION_ACTIVE )) && zle kill-region; zle .self-insert; }
      zle -N self-insert .zle_self_insert

      .zle_backward_delete_char() { (( REGION_ACTIVE )) && zle kill-region || zle .backward-delete-char; }
      zle -N backward-delete-char .zle_backward_delete_char

      .zle_delete_char() { (( REGION_ACTIVE )) && zle kill-region || zle .delete-char; }
      zle -N delete-char .zle_delete_char

      # --- Normal Movement (Clears Selection & Snaps to Bounds) ---
      .zle_backward_char() {
          if (( REGION_ACTIVE )); then
              REGION_ACTIVE=0
              CURSOR=$(( CURSOR < MARK ? CURSOR : MARK ))
          else
              zle .backward-char
          fi
      }
      zle -N backward-char .zle_backward_char

      .zle_forward_char() {
          if (( REGION_ACTIVE )); then
              REGION_ACTIVE=0
              CURSOR=$(( CURSOR > MARK ? CURSOR : MARK ))
          else
              zle .forward-char
          fi
      }
      zle -N forward-char .zle_forward_char

      .zle_backward_word() {
          if (( REGION_ACTIVE )); then
              REGION_ACTIVE=0
              CURSOR=$(( CURSOR < MARK ? CURSOR : MARK ))
          else
              zle .backward-word
          fi
      }
      zle -N backward-word .zle_backward_word

      .zle_forward_word() {
          if (( REGION_ACTIVE )); then
              REGION_ACTIVE=0
              CURSOR=$(( CURSOR > MARK ? CURSOR : MARK ))
          else
              zle .forward-word
          fi
      }
      zle -N forward-word .zle_forward_word

      # --- Shift Selection Logic ---
      .zle_shift_backward_char() { (( REGION_ACTIVE )) || MARK=$CURSOR; REGION_ACTIVE=1; zle .backward-char; }
      zle -N shift-backward-char .zle_shift_backward_char

      .zle_shift_forward_char() { (( REGION_ACTIVE )) || MARK=$CURSOR; REGION_ACTIVE=1; zle .forward-char; }
      zle -N shift-forward-char .zle_shift_forward_char

      .zle_shift_backward_word() { (( REGION_ACTIVE )) || MARK=$CURSOR; REGION_ACTIVE=1; zle .backward-word; }
      zle -N shift-backward-word .zle_shift_backward_word

      .zle_shift_forward_word() { (( REGION_ACTIVE )) || MARK=$CURSOR; REGION_ACTIVE=1; zle .forward-word; }
      zle -N shift-forward-word .zle_shift_forward_word

      # -----------------------------------------------------------------------------
      # KEYBINDINGS
      # -----------------------------------------------------------------------------
      # Custom Select All
      bindkey -M emacs '^a' .zle_select-all
      bindkey '^a' .zle_select-all

      # Deletion
      bindkey '^[[3~' delete-char            # Delete
      bindkey '^[[3;5~' kill-word            # Ctrl+Delete
      bindkey '^H' backward-kill-word        # Ctrl+Backspace

      # Normal Arrow Navigation
      bindkey '^[[D' backward-char           # Left Arrow
      bindkey '^[OD' backward-char           # Left Arrow (Fallback)
      bindkey '^[[C' forward-char            # Right Arrow
      bindkey '^[OC' forward-char            # Right Arrow (Fallback)

      # Ctrl+Arrow Navigation
      bindkey '^[[1;5D' backward-word        # Ctrl+Left
      bindkey '^[[1;5C' forward-word         # Ctrl+Right

      # Shift+Arrow Selection
      bindkey '^[[1;2D' shift-backward-char  # Shift+Left
      bindkey '^[[1;2C' shift-forward-char   # Shift+Right

      # Shift+Ctrl+Arrow Selection
      bindkey '^[[1;6D' shift-backward-word  # Shift+Ctrl+Left
      bindkey '^[[1;6C' shift-forward-word   # Shift+Ctrl+Right
    '';
  };

  # 6. PROMPTS
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    
    settings = {
      add_newline = true;
      command_timeout = 200;
      format = "[$directory$git_branch$git_status]($style)$character";

      character = {
        error_symbol = "[✗](bold cyan)";
        success_symbol = "[❯](bold cyan)";
      };

      directory = {
        truncation_length = 2;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
      };

      git_branch = {
        format = "[$branch]($style) ";
        style = "italic cyan";
      };

      git_status = {
        format = "[$all_status]($style)";
        style = "cyan";
        ahead = "⇡\${count} ";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count} ";
        behind = "⇣\${count} ";
        conflicted = " ";
        up_to_date = " ";
        untracked = "? ";
        modified = " ";
        stashed = "";
        staged = "";
        renamed = "";
        deleted = "";
      };
    };
  };
}
