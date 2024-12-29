# !Oh-my-szh Configuration

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Case-sensitive completion.
CASE_SENSITIVE="false"

# Hyphen-insensitive completion. _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"

# Auto-update behavior;
# zstyle ':omz:update' mode disabled
zstyle ':omz:update' mode auto
# zstyle ':omz:update' mode reminder

# Command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Command execution time stamp shown in the history command output.
HIST_STAMPS="mm/dd/yyyy"

# Standard plugins: $ZSH/plugins/
# Custom plugins: $ZSH_CUSTOM/plugins/
plugins=(
    bazel
    git
    macos #https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/macos
    sublime
    vscode # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/vscode
    zsh-completions
    zsh-interactive-cd
    zsh-autosuggestions
    zsh-syntax-highlighting
)

#Autocompletions
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

source $ZSH/oh-my-zsh.sh

# !User Configuration

# Personal 'alias's

# Update Homebrew data, formulae, and casks, then run cleanup
alias bup="brew update && brew upgrade && \
if [ \$(brew list --cask | wc -l) -gt 0 ]; then \
  for cask in \$(brew list --cask); do \
    brew upgrade --cask \"\$cask\"; \
  done; \
fi && \
brew autoremove && brew cleanup --prune=all"
# Homebrew uninstall with zap
alias buz="brew uninstall --zap"

# quick alias to desktop
alias desk="cd ~/Desktop"
# get machine's ip address
alias ip="ipconfig getifaddr en0"
#alias python3 -> python
alias python="python3"

#edit global zsh configuration
alias zshconfig="code ~/.zshrc"
# reload zsh configuration
alias zshsource="source ~/.zshrc"

# reload zsh configuration
alias ohmyzsh="cd ~/.oh-my-zsh"

# navigate to global ssh directory
alias sshhome="cd ~/.ssh"
# edit global ssh configuration
alias sshconfig="code ~/.ssh/config"

# edit global git configuration
alias gitconfig="code ~/.gitconfig"

# git aliases
alias gits="git status"
alias gitd="git diff"
alias gitl="git lg"
alias gita="git add ."
alias gitc="cz commit"

# type sublime . to open current folder in Sublime Text
alias sublime="/Applications/Sublime\ Text.app/Contents/SharedSupport/bin/subl --new-window $@"

# load zsh-completions
autoload -U compinit && compinit

# TheFuck console error correction
eval $(thefuck --alias)

# fnm Configuartion
export PATH="/Users/drew/Library/Application Support/fnm:$PATH"
eval "$(fnm env --use-on-cd)"

# pnpm Configuration
export PNPM_HOME="/Users/drewgiacomi/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

PATH=~/.console-ninja/.bin:$PATH
[[ -s "/Users/drew/.gvm/scripts/gvm" ]] && source "/Users/drew/.gvm/scripts/gvm"

# Starship must come at the end!
eval "$(starship init zsh)"
