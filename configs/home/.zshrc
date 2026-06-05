# Interactive shell configuration only
# PATH and env setup is in .zshenv (available to all shell types)

if [[ "$TERM_PROGRAM" == "iTerm.app" ]] || [[ -n "$ITERM_SESSION_ID" ]]; then
  export ITERM_DETECTED=1
fi

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ~="cd $HOME"

colorflag="--color"
alias l="ls -l ${colorflag}"
alias la="ls -la ${colorflag}"
alias lsd='ls -l ${colorflag} | grep "^d"'
alias ls="command ls ${colorflag}"
export LS_COLORS='no=00:fi=00:di=01;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:'
export COLORTERM=truecolor

alias w="cd ~/workspace"

# Setup pure prompt
fpath+=($HOME/.zsh/pure $HOME/.zsh/completions)
autoload -U promptinit; promptinit
zstyle :prompt:pure:prompt:success color '#FF6B00'
zstyle :prompt:pure:prompt:error color '#FF6B00'
prompt pure
PROMPT='%B%F{#FF6B00}[%m]%f%b '$PROMPT

# nvm (full version switching for interactive use)
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

autoload -Uz compinit && compinit

[[ -f ~/.extras ]] && source ~/.extras

# Auto-attach to tmux session for session persistence
if command -v tmux &> /dev/null && [[ -z "$TMUX" ]] && [[ $- == *i* ]] && [[ -z "$AC_NO_TMUX" ]]; then
  if [[ -n "$ITERM_DETECTED" ]]; then
    tmux -CC new-session -A -s agent
  else
    tmux new-session -A -s agent
  fi
fi

cd ~/workspace 2>/dev/null || true
