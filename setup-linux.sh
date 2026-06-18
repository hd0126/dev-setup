#!/usr/bin/env bash
# Linux (Ubuntu/Debian) setup script
# Usage: bash setup-linux.sh

set -e
START_TIME=$SECONDS

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[..] $1${NC}"; }
warn() { echo -e "${YELLOW}[!!] $1${NC}"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# ── 1. System packages ────────────────────────────────────
info "Updating apt..."
sudo apt-get update -q

install_apt() {
    if ! dpkg -s "$1" &>/dev/null; then
        info "Installing $1..."
        sudo apt-get install -y -q "$1" && ok "$1" || fail "$1"
    else
        ok "$1 (already installed)"
    fi
}

install_apt curl
install_apt git
install_apt unzip
install_apt ripgrep
install_apt fzf
install_apt python3
install_apt python3-pip

# ── 2. GitHub CLI ─────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    info "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -q && sudo apt-get install -y -q gh && ok "GitHub CLI" || fail "GitHub CLI"
else
    ok "GitHub CLI (already installed)"
fi

# ── 4. Node.js LTS (nvm) ──────────────────────────────────
if ! command -v node &>/dev/null; then
    info "Installing Node.js LTS via nvm..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts && ok "Node.js LTS" || fail "Node.js LTS"
else
    ok "Node.js (already installed: $(node --version))"
fi

# nvm 로드 (이미 설치된 경우 포함)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ── 5. Starship ───────────────────────────────────────────
if ! command -v starship &>/dev/null; then
    info "Installing Starship..."
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes && ok "Starship" || fail "Starship"
else
    ok "Starship (already installed)"
fi

# ── 6. zoxide ─────────────────────────────────────────────
if ! command -v zoxide &>/dev/null; then
    info "Installing zoxide..."
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash && ok "zoxide" || fail "zoxide"
else
    ok "zoxide (already installed)"
fi

# ── 7. npm global packages ────────────────────────────────
install_npm() {
    local pkg="$1"
    local installed latest
    installed=$(npm list -g --depth=0 2>/dev/null | grep -F "$pkg@" | grep -oP '\d+\.\d+\.\d+\S*' | head -1)
    latest=$(npm view "$pkg" version 2>/dev/null)
    if [ -z "$installed" ]; then
        info "Installing $pkg..."
        npm install -g --no-fund --loglevel=error "$pkg" && ok "$pkg" || fail "$pkg"
    elif [ "$installed" != "$latest" ]; then
        info "Updating $pkg ($installed → $latest)..."
        npm install -g --no-fund --loglevel=error "$pkg" && ok "$pkg" || fail "$pkg"
    else
        ok "$pkg (already up to date: $installed)"
    fi
}

if command -v npm &>/dev/null; then
    install_npm "@anthropic-ai/claude-code"
    install_npm "@openai/codex"
    install_npm "@google/gemini-cli"
    install_npm "oh-my-claude-sisyphus"
    install_npm "oh-my-codex"
else
    warn "npm not found — skipping AI CLI tools. Install Node.js first, then re-run."
fi

# ── 8. Shell config (.bashrc / .zshrc) ───────────────────
SHELL_CONFIGS=()
[ -f "$HOME/.bashrc" ] && SHELL_CONFIGS+=("$HOME/.bashrc")
[ -f "$HOME/.zshrc"  ] && SHELL_CONFIGS+=("$HOME/.zshrc")
# 현재 셸이 zsh인데 .zshrc가 없으면 생성
if [[ "$SHELL" == */zsh ]] && [[ ! -f "$HOME/.zshrc" ]]; then
    touch "$HOME/.zshrc"
    SHELL_CONFIGS+=("$HOME/.zshrc")
fi
[ ${#SHELL_CONFIGS[@]} -eq 0 ] && SHELL_CONFIGS+=("$HOME/.bashrc") # fallback

SNIPPET=$(cat <<'SHELLSNIPPET'
# ── Shell startup timer ───────────────────────────────────
_shell_start=$(date +%s%3N)

# ── Claude Code shortcuts ──────────────────────────────────
alias cc='claude --dangerously-skip-permissions'
alias ccc='cc --continue'
alias ccr='cc --resume'

# ── zoxide ────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash --cmd z)"
fi

# ── fzf ───────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    eval "$(fzf --bash 2>/dev/null || true)"
fi

# ── Starship prompt (cached) ──────────────────────────────
if command -v starship &>/dev/null; then
    _starship_cache="${XDG_CACHE_HOME:-$HOME/.cache}/starship_init_bash.sh"
    if [ ! -f "$_starship_cache" ]; then
        mkdir -p "$(dirname "$_starship_cache")"
        starship init bash > "$_starship_cache"
    fi
    source "$_starship_cache"
fi

# ── nvm ───────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %dms\033[0m\n' "$(( $(date +%s%3N) - _shell_start ))"
    unset _shell_start
fi
SHELLSNIPPET
)

ZSH_SNIPPET=$(cat <<'ZSHSNIPPET'
# ── Shell startup timer ───────────────────────────────────
zmodload zsh/datetime
_shell_start=$EPOCHREALTIME

# ── Claude Code shortcuts ──────────────────────────────────
alias cc='claude --dangerously-skip-permissions'
alias ccc='cc --continue'
alias ccr='cc --resume'

# ── zoxide ────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh --cmd z)"
fi

# ── fzf ───────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    source <(fzf --zsh 2>/dev/null || true)
fi

# ── Starship prompt (cached) ──────────────────────────────
if command -v starship &>/dev/null; then
    _starship_cache="${XDG_CACHE_HOME:-$HOME/.cache}/starship_init_zsh.zsh"
    if [ ! -f "$_starship_cache" ]; then
        mkdir -p "$(dirname "$_starship_cache")"
        starship init zsh > "$_starship_cache"
    fi
    source "$_starship_cache"
fi

# ── nvm ───────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
ZSHSNIPPET
)

MARKER="# ── Claude Code shortcuts ──────────────────────────────────"

for cfg in "${SHELL_CONFIGS[@]}"; do
    if grep -q "$MARKER" "$cfg" 2>/dev/null; then
        warn "$cfg — already configured, skipping"
    else
        if [[ "$cfg" == *".zshrc" ]]; then
            echo "$ZSH_SNIPPET" >> "$cfg"
        else
            echo "$SNIPPET" >> "$cfg"
        fi
        ok "$cfg updated"
    fi
done

# ── 9. SSH agent ──────────────────────────────────────────
# macOS와 달리 Linux는 자동 관리 안 되므로 .bashrc/.zshrc에 추가
SSH_AGENT_SNIPPET=$(cat <<'SSHSNIPPET'

# ── SSH agent ─────────────────────────────────────────────
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" &>/dev/null
    ssh_key=$(find "$HOME/.ssh" -maxdepth 1 -type f ! -name "*.pub" ! -name "known_hosts" ! -name "config" | head -1)
    [ -n "$ssh_key" ] && ssh-add "$ssh_key" &>/dev/null
fi
SSHSNIPPET
)

SSH_MARKER="# ── SSH agent ─────────────────────────────────────────────"
for cfg in "${SHELL_CONFIGS[@]}"; do
    if ! grep -q "$SSH_MARKER" "$cfg" 2>/dev/null; then
        echo "$SSH_AGENT_SNIPPET" >> "$cfg"
        ok "SSH agent config → $cfg"
    fi
done

# ── Done ──────────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${CYAN}  Done in ${ELAPSED}s${NC}"
echo -e "${CYAN}  NEXT STEP: Open a new terminal to apply${NC}"
echo -e "${CYAN}  changes, then run: cc --version${NC}"
echo -e "${GREEN}=============================================${NC}"
