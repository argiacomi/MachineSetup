export ZSH="${ZSH:-$HOME/.oh-my-zsh}"

# Deduplicate PATH/fpath as entries are added.
typeset -gU path PATH fpath

CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"
HIST_STAMPS="mm/dd/yyyy"

# Must precede oh-my-zsh.sh, which only raises these, never lowers them.
HISTSIZE=100000
SAVEHIST=100000

zstyle ':omz:update' mode auto

# Skips OMZ's compaudit/compfix security prompt
ZSH_DISABLE_COMPFIX=true

# Skips OMZ's url-quote-magic / bracketed-paste-magic ZLE widgets
DISABLE_MAGIC_FUNCTIONS=true

# Add package-manager bins before OMZ initializes completions.
export PNPM_HOME="/Users/drew/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# Rust/Cargo
[[ -r "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# uv tools
path=("$HOME/.local/bin" $path)

# Add extra completion definitions before Oh My Zsh initializes completions.
fpath=("${ZSH_CUSTOM:-${ZSH}/custom}/plugins/zsh-completions/src" $fpath)

# fzf: Ctrl-T / Alt-C source commands.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# Suggest matching aliases before each command. Costs ~40ms per command.
zstyle ':omz:plugins:alias-finder' autoload yes

# Every plugin is startup work, so keep this list deliberate.
# zsh-syntax-highlighting must stay LAST: it wraps already-defined widgets.
plugins=(
    git
    zsh-completions
    sudo
    extract
    colored-man-pages
    command-not-found
    alias-finder
    fzf
    zoxide
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# Drops every older duplicate, not just back-to-back ones like OMZ does.
setopt hist_ignore_all_dups
setopt hist_reduce_blanks

# bazelisk ships bazel's completion but registers none of its own.
compdef bazelisk=bazel

# Generated completions live in ~/.oh-my-zsh/custom/completions (already on fpath).
# To refresh one, regenerate it then delete $ZSH_COMPDUMP:
#   rustup completions zsh              > ~/.oh-my-zsh/custom/completions/_rustup
#   ruff generate-shell-completion zsh  > ~/.oh-my-zsh/custom/completions/_ruff

cleanup_space() {
    emulate -L zsh
    setopt pipe_fail err_return null_glob

    local mode="${1:-preview}"
    local cleanup_failures=0
    local user_uid

    user_uid="$(id -u)"

    # Usually safe to clear. Some Apple-managed items are TCC-protected and
    # will be silently skipped unless the terminal has Full Disk Access.
    local -a user_paths=(
        "$HOME/Library/Caches"
        "$HOME/Library/Logs"
        "$HOME/Library/DiagnosticReports"
        "$HOME/Library/Application Support/CrashReporter"
        "$HOME/Library/Saved Application State"
        "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

        # App/container caches often counted as System Data.
        "$HOME"/Library/Containers/*/Data/Library/Caches(N)
        "$HOME"/Library/Group\ Containers/*/Library/Caches(N)

        # Developer caches, safe to rebuild.
        "$HOME/Library/Developer/Xcode/DerivedData"
        "$HOME/Library/Developer/Xcode/iOS Device Logs"
        "$HOME/Library/Developer/CoreSimulator/Caches"
    )

    # Optional because these may contain data you intentionally want.
    local ios_backups="$HOME/Library/Application Support/MobileSync/Backup"
    local trash="$HOME/.Trash"

    # Finder combines the home Trash with Trash folders on mounted volumes.
    local -a volume_trashes
    volume_trashes=(/Volumes/*/.Trashes/${user_uid}(N))

    _show_size() {
        local p="$1"

        [[ -e "$p" ]] || return 0

        du -sh "$p" 2>/dev/null || true

        return 0
    }

    _show_size_nonzero() {
        local p="$1"
        local kb

        [[ -e "$p" ]] || return 1

        kb="$(du -sk "$p" 2>/dev/null | awk '{print $1}')" || return 1

        [[ -n "$kb" && "$kb" == <-> && "$kb" -gt 0 ]] || return 1

        du -sh "$p" 2>/dev/null || return 1
        return 0
    }

    # Free space on / in 1K blocks. -P prevents a long device name wrapping.
    _free_kb() {
        local kb

        kb="$(df -Pk / 2>/dev/null | tail -1 | awk '{print $4}')" || kb=""

        [[ -n "$kb" && "$kb" == <-> ]] || kb=0

        print -r -- "$kb"
        return 0
    }

    _human_kb() {
        local kb="${1:-0}"
        local sign=""

        if (( kb < 0 )); then
            sign="-"
            kb=$(( -kb ))
        fi

        if (( kb >= 1048576 )); then
            printf '%s%.2f GB' "$sign" "$(( kb / 1048576.0 ))"
        elif (( kb >= 1024 )); then
            printf '%s%.1f MB' "$sign" "$(( kb / 1024.0 ))"
        else
            printf '%s%d KB' "$sign" "$kb"
        fi

        return 0
    }

    _show_big_files() {
        local base="$1"

        [[ -d "$base" ]] || return 0

        find "$base" -type f -size +200M -exec du -h {} + 2>/dev/null \
            | sort -hr \
            | head -20 || true

        return 0
    }

    # Skips TCC/SIP-protected items silently; returns 1 if anything was missed.
    _clear_dir_contents() {
        local p="$1"

        [[ -d "$p" ]] || return 0

        if ! find "$p" \
            -mindepth 1 \
            -maxdepth 1 \
            -exec rm -rf -- {} + 2>/dev/null
        then
            return 1
        fi

        return 0
    }

    _show_trash_sizes() {
        local p
        local found=0

        if [[ -d "$trash" ]]; then
            echo "Home Trash:"
            _show_size "$trash"
            found=1
        fi

        for p in "${volume_trashes[@]}"; do
            echo "Mounted-volume Trash:"
            _show_size "$p"
            found=1
        done

        if (( ! found )); then
            echo "No accessible Trash directories found."
        fi

        return 0
    }

    _empty_trash() {
        local p
        local failed=0

        # Finder handles the home Trash and Trash on mounted volumes.
        if command -v osascript >/dev/null 2>&1; then
            if osascript -e 'tell application "Finder" to empty trash' \
                >/dev/null 2>&1
            then
                return 0
            fi
        fi

        if ! _clear_dir_contents "$trash"; then
            failed=1
        fi

        for p in "${volume_trashes[@]}"; do
            if ! _clear_dir_contents "$p"; then
                failed=1
            fi
        done

        return "$failed"
    }

    _show_package_caches() {
        local cache_path

        echo
        echo "=== Package manager caches ==="

        if command -v brew >/dev/null 2>&1; then
            echo "Homebrew cache:"
            cache_path="$(brew --cache 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        fi

        if command -v npm >/dev/null 2>&1; then
            echo "npm cache:"
            cache_path="$(npm config get cache 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        fi

        if command -v yarn >/dev/null 2>&1; then
            echo "Yarn cache:"
            cache_path="$(yarn cache dir 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        fi

        if command -v pnpm >/dev/null 2>&1; then
            echo "pnpm store:"
            cache_path="$(pnpm store path 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        fi

        if command -v pip3 >/dev/null 2>&1; then
            echo "pip cache:"
            cache_path="$(pip3 cache dir 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        elif command -v pip >/dev/null 2>&1; then
            echo "pip cache:"
            cache_path="$(pip cache dir 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        fi

        if command -v go >/dev/null 2>&1 \
            && go env GOROOT >/dev/null 2>&1
        then
            echo "Go build cache:"
            cache_path="$(go env GOCACHE 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"

            echo "Go module cache:"
            cache_path="$(go env GOMODCACHE 2>/dev/null || true)"
            [[ -n "$cache_path" ]] && _show_size "$cache_path"
        elif command -v go >/dev/null 2>&1; then
            echo "Go cache: unavailable because the Go environment is broken."
        fi

        return 0
    }

    _clean_package_caches() {
        echo
        echo "=== Cleaning package manager caches ==="

        if command -v brew >/dev/null 2>&1; then
            brew cleanup -s || true
            brew autoremove || true
        fi

        if command -v npm >/dev/null 2>&1; then
            npm cache clean --force 2>/dev/null || true
        fi

        if command -v yarn >/dev/null 2>&1; then
            yarn cache clean || true
        fi

        if command -v pnpm >/dev/null 2>&1; then
            pnpm store prune || true
        fi

        if command -v pip3 >/dev/null 2>&1; then
            pip3 cache purge 2>/dev/null || true
        elif command -v pip >/dev/null 2>&1; then
            pip cache purge 2>/dev/null || true
        fi

        if command -v conda >/dev/null 2>&1; then
            conda clean -a -y || true
        fi

        if command -v gem >/dev/null 2>&1; then
            gem cleanup || true
        fi

        if command -v go >/dev/null 2>&1 \
            && go env GOROOT >/dev/null 2>&1
        then
            go clean -cache -testcache 2>/dev/null || true

            if [[ "${CLEAR_GO_MODCACHE:-0}" == "1" ]]; then
                go clean -modcache 2>/dev/null || true
            fi
        elif command -v go >/dev/null 2>&1; then
            cleanup_failures=1
        fi

        return 0
    }

    echo
    echo "=== User cache/log/temp targets ==="

    local printed_user_target=0
    local p

    for p in "${user_paths[@]}"; do
        if _show_size_nonzero "$p"; then
            printed_user_target=1
        fi
    done

    if (( ! printed_user_target )); then
        echo "No readable, non-empty user cache/log/temp targets found."
    fi

    echo
    echo "=== Optional user data targets ==="
    echo "iOS/iPadOS local backups:"
    _show_size "$ios_backups"

    echo
    echo "Trash:"
    _show_trash_sizes

    echo
    echo "=== System cache/log/temp targets ==="
    sudo sh -c '
        for p in \
            "/Library/Caches" \
            "/Library/Logs" \
            "/Library/DiagnosticReports" \
            "/private/tmp" \
            "/private/var/tmp" \
            "/Library/Updates"
        do
            if [ -e "$p" ]; then
                du -sh "$p" 2>/dev/null || true
            fi
        done
    ' || true

    echo
    echo "=== Time Machine local snapshots ==="
    if command -v tmutil >/dev/null 2>&1; then
        tmutil listlocalsnapshots / 2>/dev/null || true
    else
        echo "tmutil not found"
    fi

    echo
    echo "=== APFS snapshots ==="
    diskutil apfs listSnapshots / 2>/dev/null || true

    echo
    echo "=== macOS installer apps in /Applications ==="
    find /Applications \
        -maxdepth 1 \
        -name "Install macOS*.app" \
        -exec du -sh {} + 2>/dev/null \
        | sort -hr || true

    echo
    echo "=== Large files in user cache/log/temp locations (>200MB) ==="
    for p in "${user_paths[@]}"; do
        _show_big_files "$p"
    done

    _show_package_caches

    echo
    echo "=== Docker reclaimable usage ==="
    if command -v docker >/dev/null 2>&1; then
        docker system df || true
        echo
        docker system df -v || true
    else
        echo "docker not found"
    fi

    echo
    echo "=== Docker Desktop disk image/cache locations ==="
    _show_size "$HOME/Library/Containers/com.docker.docker/Data/vms/0"
    _show_size "$HOME/Library/Group Containers/group.com.docker"

    if [[ "$mode" != "--run" ]]; then
        echo
        echo "Preview only. Run:"
        echo "  cleanup_space --run"
        echo
        echo "Optional flags:"
        echo "  REMOVE_IOS_BACKUPS=1 cleanup_space --run"
        echo "  EMPTY_TRASH=1 cleanup_space --run"
        echo "  REMOVE_MACOS_UPDATE_CACHE=1 cleanup_space --run"
        echo "  REMOVE_MACOS_INSTALLERS=1 cleanup_space --run"
        echo "  DOCKER_PRUNE_VOLUMES=1 cleanup_space --run"
        echo "  CLEAR_GO_MODCACHE=1 cleanup_space --run"
        echo
        echo "Combine flags as needed:"
        echo "  EMPTY_TRASH=1 DOCKER_PRUNE_VOLUMES=1 cleanup_space --run"
        return 0
    fi

    # Baseline for the closing summary. Taken here so the read-only preview
    # scans above cannot be counted as reclaimed space.
    local free_before free_after freed
    free_before="$(_free_kb)"

    echo
    echo "=== Cleaning user targets ==="

    for p in "${user_paths[@]}"; do
        if ! _clear_dir_contents "$p"; then
            cleanup_failures=1
        fi
    done

    echo
    echo "=== Cleaning system targets ==="

    if ! sudo sh -c '
        failed=0

        for p in \
            "/Library/Caches" \
            "/Library/Logs" \
            "/Library/DiagnosticReports" \
            "/private/tmp" \
            "/private/var/tmp"
        do
            if [ -d "$p" ]; then
                find "$p" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf -- {} + 2>/dev/null || failed=1
            fi
        done

        exit "$failed"
    '; then
        cleanup_failures=1
    fi

    if [[ "${REMOVE_MACOS_UPDATE_CACHE:-0}" == "1" ]]; then
        echo
        echo "=== Cleaning macOS update cache ==="

        if ! sudo sh -c '
            if [ -d "/Library/Updates" ]; then
                find "/Library/Updates" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf -- {} + 2>/dev/null
            fi
        '; then
            cleanup_failures=1
        fi
    fi

    if [[ "${REMOVE_MACOS_INSTALLERS:-0}" == "1" ]]; then
        echo
        echo "=== Removing macOS installer apps ==="

        if ! sudo find /Applications \
            -maxdepth 1 \
            -name "Install macOS*.app" \
            -exec rm -rf -- {} + 2>/dev/null
        then
            cleanup_failures=1
        fi
    fi

    echo
    echo "=== Thinning Time Machine local snapshots ==="

    if command -v tmutil >/dev/null 2>&1; then
        sudo tmutil thinlocalsnapshots \
            / \
            "${TMUTIL_PURGE_BYTES:-100000000000}" \
            4 2>/dev/null || true
    fi

    echo
    echo "=== Resetting Quick Look cache ==="

    if command -v qlmanage >/dev/null 2>&1; then
        qlmanage -r cache 2>/dev/null || true
    fi

    echo
    echo "=== Cleaning unavailable iOS simulators ==="

    if command -v xcrun >/dev/null 2>&1; then
        xcrun simctl delete unavailable 2>/dev/null || true
    fi

    if [[ "${REMOVE_IOS_BACKUPS:-0}" == "1" ]]; then
        echo
        echo "=== Removing local iOS/iPadOS backups ==="

        if ! _clear_dir_contents "$ios_backups"; then
            cleanup_failures=1
        fi
    fi

    if [[ "${EMPTY_TRASH:-0}" == "1" ]]; then
        echo
        echo "=== Emptying Trash ==="

        if ! _empty_trash; then
            cleanup_failures=1
        fi

        echo
        echo "=== Remaining Trash usage ==="
        _show_trash_sizes
    fi

    _clean_package_caches

    echo
    echo "=== Cleaning Docker ==="

    if command -v docker >/dev/null 2>&1; then
        docker system prune -af || true
        docker buildx prune -af 2>/dev/null \
            || docker builder prune -af 2>/dev/null \
            || true

        if [[ "${DOCKER_PRUNE_VOLUMES:-0}" == "1" ]]; then
            docker volume prune -af 2>/dev/null \
                || docker volume prune -f 2>/dev/null \
                || true
        fi
    fi

    echo
    echo "=== Remaining Docker usage ==="

    if command -v docker >/dev/null 2>&1; then
        docker system df || true
    else
        echo "docker not found"
    fi

    echo
    echo "=== Remaining Time Machine local snapshots ==="

    if command -v tmutil >/dev/null 2>&1; then
        tmutil listlocalsnapshots / 2>/dev/null || true
    fi

    # Assignment form, not (( freed = ... )): an arithmetic command whose result
    # is 0 returns 1, and err_return is set, so reclaiming exactly nothing would
    # abort the function right before it printed the summary.
    free_after="$(_free_kb)"
    freed=$(( free_after - free_before ))

    echo
    echo "=== Space reclaimed ==="
    printf 'Free before:  %s\n' "$(_human_kb "$free_before")"
    printf 'Free after:   %s\n' "$(_human_kb "$free_after")"
    printf 'Reclaimed:    %s\n' "$(_human_kb "$freed")"
    echo
    echo "Measured as free space on / before vs after. Docker and APFS/Time"
    echo "Machine snapshot deletion keep reclaiming in the background, so the"
    echo "real figure may grow for a few minutes after this returns."

    echo

    if (( cleanup_failures )); then
        echo "Done. Some protected items were skipped (this is normal)."
        echo "To include them, grant your terminal Full Disk Access in"
        echo "System Settings > Privacy & Security > Full Disk Access."
    else
        echo "Done."
    fi

    echo "Reboot to let macOS recreate temporary folders and caches cleanly."
}

bup() {
    brew update && brew upgrade || return

    local cask
    for cask in $(brew list --cask 2>/dev/null); do
        [[ "$cask" == font-* ]] && continue
        brew upgrade --cask "$cask"
    done

    brew autoremove && brew cleanup --prune=all
    local rc=$?

    # Node lives under fnm, not brew, but belongs in the same sweep.
    # `|| true` keeps a Node failure from masking the brew exit status.
    if (( $+commands[fnm] )); then
        print
        fnmup || true
    fi

    return $rc
}

# Explicitly-installed formulae with their dependencies, then casks.
brews() {
    local formulae="$(brew leaves | xargs brew deps --installed --for-each)"
    local casks="$(brew list --cask 2>/dev/null)"

    local blue="$(tput setaf 4)"
    local bold="$(tput bold)"
    local off="$(tput sgr0)"

    echo "${blue}==>${off} ${bold}Formulae${off}"
    echo "${formulae}" | sed "s/^\(.*\):\(.*\)$/\1${blue}\2${off}/"
    echo "\n${blue}==>${off} ${bold}Casks${off}\n${casks}"
}

# Brew aliases from the OMZ plugin, minus `bup`/`bubu`/`bubug`, which would
# shadow the bup function above.
alias bi='brew install'
alias bih='brew install --HEAD'
alias br='brew reinstall'
alias brh='brew reinstall --HEAD'
alias bl='brew list'
alias bo='brew outdated'
alias bs='brew search'
alias bu='brew update'
alias bubo='brew update && brew outdated'
alias bfu='brew upgrade --formula'
alias bugbc='brew upgrade --greedy && brew cleanup'
alias ba='brew autoremove'
alias bcn='brew cleanup'
alias bdr='brew doctor'
alias bcfg='brew config'
alias brewp='brew pin'
alias brewsp='brew list --pinned'
alias buz='brew uninstall --zap'

# Cask equivalents.
alias bci='brew info --cask'
alias bcin='brew install --cask'
alias bcl='brew list --cask'
alias bco='brew outdated --cask'
alias bcrin='brew reinstall --cask'
alias bcup='brew upgrade --cask'

# brew services.
alias bsl='brew services list'
alias bson='brew services start'
alias bsona='bson --all'
alias bsoff='brew services stop'
alias bsoffa='bsoff --all'
alias bsr='brew services run'
alias bsra='bsr --all'

# Directory shortcuts.
alias desk='cd ~/Desktop'
alias sshhome='cd ~/.ssh'
alias ohmyzsh='cd ~/.oh-my-zsh'

# Config file shortcuts.
alias zshconfig='code ~/.zshrc'
alias zshsource='source ~/.zshrc'
alias sshconfig='code ~/.ssh/config'
alias gitconfig='code ~/.gitconfig'

# Utility shortcuts.
alias ipadd='ipconfig getifaddr en0'

# Last 20 commands; a bare `history` dumps the entire list under OMZ.
alias h='omz_history -f -20'

# Git shortcuts.
alias gits='git status'
alias gitd='git diff'
alias gitl='git lg'
alias gita='git add .'
alias gitc='cz commit'

sublime() {
    /Applications/Sublime\ Text.app/Contents/SharedSupport/bin/subl --new-window "$@"
}

# Optional tools: lazy-loaded where startup cost is high.
# Use zsh's $commands hash instead of spawning `command -v` checks.

# thefuck: avoid running `thefuck --alias` during startup.
alias fuck='eval $(thefuck $(fc -ln -1 | tail -n 1)); fc -R'

# fnm: lazy by default, so the first node/npm call pays the setup cost.
# Set FAST_FNM_LAZY=0 above for immediate --use-on-cd behavior.
: ${FAST_FNM_LAZY:=1}
if (( $+commands[fnm] )); then
    if [[ "$FAST_FNM_LAZY" == "0" ]]; then
        eval "$(fnm env --use-on-cd)"
    else
        # Wrap only installed commands; an absent one would pay the full fnm
        # setup cost before failing. pnpm is here because it needs node on PATH.
        __fnm_lazy_load() {
            unfunction node npm npx pnpm 2>/dev/null || true
            eval "$(fnm env --shell zsh)"
        }
        node() { __fnm_lazy_load; command node "$@"; }
        npm() { __fnm_lazy_load; command npm "$@"; }
        npx() { __fnm_lazy_load; command npx "$@"; }
        pnpm() { __fnm_lazy_load; command pnpm "$@"; }
    fi
fi

# Install the newest remote Node, point use/default at it, drop the old one.
#   fnmup            latest release
#   fnmup --lts      latest LTS instead
#   fnmup -n         show what would happen, change nothing
fnmup() {
    emulate -L zsh
    setopt local_options pipe_fail

    (( $+commands[fnm] )) || { print -u2 "fnmup: fnm not found"; return 1 }

    local dry_run=0 lts=0
    while (( $# )); do
        case "$1" in
            -n|--dry-run) dry_run=1 ;;
            -l|--lts)     lts=1 ;;
            -h|--help)
                print "usage: fnmup [-n|--dry-run] [-l|--lts]"
                return 0
                ;;
            *) print -u2 "fnmup: unknown option: $1"; return 2 ;;
        esac
        shift
    done

    # `fnm use` needs the shell integration applied first. Each `fnm env` eval
    # mints a new multishell symlink, so this must not be repeated below.
    if [[ -z "$FNM_MULTISHELL_PATH" ]]; then
        eval "$(fnm env --shell zsh)" || {
            print -u2 "fnmup: could not initialise fnm env"
            return 1
        }
    fi

    local target
    if (( lts )); then
        target="$(fnm list-remote --lts --latest 2>/dev/null)"
    else
        target="$(fnm list-remote --latest 2>/dev/null)"
    fi
    # `--lts --latest` appends a codename, e.g. "v24.19.0 (Krypton)".
    target=${target%% *}
    [[ -n "$target" ]] || {
        print -u2 "fnmup: could not determine the latest remote version"
        return 1
    }

    # Newest version on disk. The grep also excludes the "system" entry, which
    # must never be uninstalled.
    local -a installed
    installed=(${(f)"$(fnm list 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"})
    local previous=""
    (( $#installed )) && previous=$(print -l $installed | sort -V | tail -1)

    if [[ -z "$previous" ]]; then
        print "fnmup: no Node installed; installing $target"
    elif [[ "$previous" == "$target" ]]; then
        print "fnmup: already on $target"
        return 0
    elif [[ "$(print -l $previous $target | sort -V | tail -1)" != "$target" ]]; then
        print "fnmup: installed $previous is newer than remote $target; nothing to do"
        return 0
    else
        print "fnmup: $previous -> $target"
    fi

    if (( dry_run )); then
        print "  would: fnm install $target && fnm use $target && fnm default $target"
        [[ -n "$previous" ]] && print "  would: fnm uninstall $previous"
        return 0
    fi

    fnm install "$target" || { print -u2 "fnmup: install failed; keeping $previous"; return 1 }
    fnm use     "$target" || { print -u2 "fnmup: 'fnm use' failed; keeping $previous"; return 1 }
    fnm default "$target" || { print -u2 "fnmup: 'fnm default' failed; keeping $previous"; return 1 }

    # Left in place, these would re-eval `fnm env` and revert the switch.
    unfunction node npm npx pnpm 2>/dev/null || true

    # Ask fnm, not `node`, so a stale wrapper cannot skew the check.
    local active="$(fnm current 2>/dev/null)"
    if [[ "$active" != "$target" ]]; then
        print -u2 "fnmup: expected $target but fnm reports '${active:-none}'; keeping $previous"
        return 1
    fi

    # Safe to remove only now that the new version is confirmed active.
    if [[ -n "$previous" && "$previous" != "$target" ]]; then
        fnm uninstall "$previous"
    fi
}

# Conda: do not run the expensive shell hook until `conda` is used.
export CONDA_EXE="/opt/homebrew/Caskroom/miniforge/base/bin/conda"
export CONDA_PYTHON_EXE="/opt/homebrew/Caskroom/miniforge/base/bin/python"
__conda_init() {
    unfunction conda 2>/dev/null || true
    local __conda_setup
    local __conda_sh="${CONDA_EXE:h:h}/etc/profile.d/conda.sh"
    __conda_setup="$("$CONDA_EXE" shell.zsh hook 2>/dev/null)"
    if [[ $? -eq 0 && -n "$__conda_setup" ]]; then
        eval "$__conda_setup"
    elif [[ -f "$__conda_sh" ]]; then
        source "$__conda_sh"
    else
        path=("${CONDA_EXE:h}" $path)
    fi
    unset __conda_setup
}
if [[ -x "$CONDA_EXE" ]]; then
    conda() { __conda_init; conda "$@"; }
fi

# Mamba: lazy-load its shell integration only when needed.
export MAMBA_EXE="/opt/homebrew/Caskroom/miniforge/base/bin/mamba"
export MAMBA_ROOT_PREFIX="/opt/homebrew/Caskroom/miniforge/base"
__mamba_init() {
    unfunction mamba 2>/dev/null || true
    local __mamba_setup
    __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh 2>/dev/null)"
    if [[ $? -eq 0 && -n "$__mamba_setup" ]]; then
        eval "$__mamba_setup"
    else
        mamba() { "$MAMBA_EXE" "$@"; }
    fi
    unset __mamba_setup
}
if [[ -x "$MAMBA_EXE" ]]; then
    mamba() { __mamba_init; mamba "$@"; }
fi

# GVM: source only when gvm/go is first used.
if [[ -s "$HOME/.gvm/scripts/gvm" ]]; then
    gvm() {
        unfunction gvm 2>/dev/null || true
        source "$HOME/.gvm/scripts/gvm"
        gvm "$@"
    }
    go() {
        unfunction go 2>/dev/null || true
        source "$HOME/.gvm/scripts/gvm"
        command go "$@"
    }
fi

# Starship: cannot be lazy-loaded, the prompt needs it at startup.
if (( $+commands[starship] )); then
    eval "$(starship init zsh)"
fi
