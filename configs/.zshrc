# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
bindkey -e
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/joelsgc/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3;5~' kill-word
bindkey '^H' backward-kill-word

source ~/.local/share/zsh/plugins/zsh-shift-select/zsh-shift-select.plugin.zsh
alias ls='eza -l --header'
alias grep='grep --color=auto'

typeset -g -a zle_highlight
zle_highlight+=(region:standout)
.zle_select-all() {
    MARK=0
    CURSOR=$#BUFFER
    REGION_ACTIVE=1
    region_highlight=("0 $#BUFFER standout")
}
zle -N .zle_select-all

.zle_self_insert() {
    if (( REGION_ACTIVE )); then
        zle kill-region
    fi
    zle .self-insert
}
zle -N self-insert .zle_self_insert

.zle_backward_delete_char() {
    if (( REGION_ACTIVE )); then
        zle kill-region
    fi
    zle .backward-delete-char
}
zle -N backward-delete-char .zle_backward_delete_char

.zle_delete_char() {
    if (( REGION_ACTIVE )); then
        zle kill-region
    fi
    zle .delete-char
}
zle -N delete-char .zle_delete_char

bindkey -M emacs '^a' .zle_select-all
bindkey '^a' .zle_select-all

eval "$(starship init zsh)"