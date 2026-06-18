#!/usr/bin/env bash
# macOS setup script
# Usage: bash setup-mac.sh

set -e
START_TIME=$SECONDS

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[..] $1${NC}"; }
warn() { echo -e "${YELLOW}[!!] $1${NC}"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# ── 1. Homebrew ───────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon PATH 설정
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew"
else
    ok "Homebrew (already installed)"
fi

install_brew() {
    if brew list "$1" &>/dev/null 2>&1; then
        ok "$1 (already installed)"
    else
        info "Installing $1..."
        brew install "$1" && ok "$1" || fail "$1"
    fi
}

# ── 2. Packages ───────────────────────────────────────────
install_brew git
install_brew gh
install_brew ripgrep
install_brew fzf
install_brew zoxide
install_brew starship
install_brew python@3.12

# ── 3. Node.js LTS (Homebrew) ─────────────────────────────
if ! command -v node &>/dev/null; then
    install_brew node
else
    ok "Node.js (already installed: $(node --version))"
fi

# ── 5. npm global packages ────────────────────────────────
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

# ── 6. Shell config (.zshrc) ─────────────────────────────
# macOS 기본 셸은 zsh
ZSHRC="$HOME/.zshrc"
[ -f "$ZSHRC" ] || touch "$ZSHRC"

MARKER="# ── Claude Code shortcuts ──────────────────────────────────"

if grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
    warn "$ZSHRC — already configured, skipping"
else
    cat >> "$ZSHRC" <<'ZSHSNIPPET'
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

# ── Homebrew (Apple Silicon) ──────────────────────────────
[ -f "/opt/homebrew/bin/brew" ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
ZSHSNIPPET
    ok "$ZSHRC updated"
fi

# ── 7. SSH agent ──────────────────────────────────────────
# macOS는 launchd + 키체인이 자동 관리 → 별도 설정 불필요
ok "SSH agent — macOS keychain handles this automatically"

# ── Done ──────────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${CYAN}  Done in ${ELAPSED}s${NC}"
echo -e "${CYAN}  NEXT STEP: Open a new terminal to apply${NC}"
echo -e "${CYAN}  changes, then run: cc --version${NC}"
echo -e "${GREEN}=============================================${NC}"
