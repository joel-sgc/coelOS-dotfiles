# =============================================================================
#  ZSH CONFIGURATION
# =============================================================================

# -----------------------------------------------------------------------------
# 1. CORE & HISTORY
# -----------------------------------------------------------------------------
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
bindkey -e

# -----------------------------------------------------------------------------
# 2. AUTOLOADS & COMPLETION
# -----------------------------------------------------------------------------
autoload -Uz compinit
compinit

# Treat all punctuation as word boundaries
WORDCHARS=''

# -----------------------------------------------------------------------------
# 3. ZLE (Zsh Line Editor) CUSTOM WIDGETS
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
# 4. KEYBINDINGS
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

# -----------------------------------------------------------------------------
# 5. ALIASES & UTILITIES
# -----------------------------------------------------------------------------
alias ls='eza -l --header'
alias grep='grep --color=auto'

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# -----------------------------------------------------------------------------
# 6. PROMPTS (MUST BE LOADED LAST)
# -----------------------------------------------------------------------------
eval "$(starship init zsh)"
# pnpm
export PNPM_HOME="~/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
