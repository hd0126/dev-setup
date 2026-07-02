#!/usr/bin/env bash
# macOS setup script
# Usage: bash setup-mac.sh

set -e
START_TIME=$SECONDS

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[..] $1${NC}"; }
warn() { echo -e "${YELLOW}[!!] $1${NC}"; }
FAILED=()
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED+=("$1"); }

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
install_brew uv

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

# Claude Code and codex ship official native installers (standalone binaries
# with background auto-update) — the vendor-recommended path. Install those
# natively, independent of npm; gemini-cli / omc / omx stay on npm.
install_native() {
    local name="$1" url="$2" sh="${3:-bash}"
    local tmp; tmp="$(mktemp)"
    info "Installing $name (native installer)..."
    # Download first, THEN run: piping `curl | sh` hides a failed download
    # (sh exits 0 on empty stdin), so a 404/network error would falsely report OK.
    if curl -fsSL "$url" -o "$tmp" && "$sh" "$tmp"; then ok "$name"; else fail "$name"; fi
    rm -f "$tmp"
}

install_native "Claude Code"    "https://claude.ai/install.sh"         bash
install_native "codex (OpenAI)" "https://chatgpt.com/codex/install.sh" sh

if command -v npm &>/dev/null; then
    install_npm "@google/gemini-cli"
    install_npm "oh-my-claude-sisyphus"
    install_npm "oh-my-codex"
else
    warn "npm not found — skipping gemini-cli/omc/omx. Install Node.js first, then re-run."
fi

# ── 6. Shell config (.zshrc) ─────────────────────────────
# macOS 기본 셸은 zsh
ZSHRC="$HOME/.zshrc"
[ -f "$ZSHRC" ] || touch "$ZSHRC"

# Re-run safe, per-feature: append each block only when its feature isn't
# already in .zshrc (signature grep). The old all-or-nothing marker check
# re-appended the WHOLE snippet on machines whose .zshrc was configured by
# hand (no marker) — duplicating aliases and inits. Hand-written equivalents
# (e.g. plain `eval "$(starship init zsh)"`) count as configured and are
# left untouched.
append_zshrc() {
    local signature="$1" label="$2" block="$3"
    if grep -qE "$signature" "$ZSHRC" 2>/dev/null; then
        ok "$label (already in .zshrc)"
    else
        printf '\n%s\n' "$block" >> "$ZSHRC"
        ok "$label → .zshrc"
    fi
}

# Startup timer must PRECEDE the feature blocks it measures, so it only makes
# sense when they're appended fresh in the same run. On a .zshrc that already
# has any of them (hand-configured), skip it — appended at the end it would
# just print a meaningless "loaded in 0ms" every shell.
HAND_CONFIGURED=0
if grep -qE 'alias cc=|zoxide init|fzf --zsh|starship init' "$ZSHRC" 2>/dev/null; then
    HAND_CONFIGURED=1
fi

if [ "$HAND_CONFIGURED" = 0 ]; then
    IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Shell startup timer ───────────────────────────────────
zmodload zsh/datetime
_shell_start=$EPOCHREALTIME
EOF
    append_zshrc '_shell_start=\$EPOCHREALTIME' "startup timer" "$BLOCK"
fi

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Claude Code shortcuts ──────────────────────────────────
alias cc='claude --dangerously-skip-permissions'
alias ccc='cc --continue'
alias ccr='cc --resume'
EOF
append_zshrc 'alias cc=' "Claude Code shortcuts (cc/ccc/ccr)" "$BLOCK"

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zoxide ────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh --cmd z)"
fi
EOF
append_zshrc 'zoxide init' "zoxide" "$BLOCK"

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fzf ───────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    source <(fzf --zsh 2>/dev/null || true)
fi
EOF
append_zshrc 'fzf --zsh' "fzf" "$BLOCK"

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Starship prompt (cached) ──────────────────────────────
if command -v starship &>/dev/null; then
    _starship_cache="${XDG_CACHE_HOME:-$HOME/.cache}/starship_init_zsh.zsh"
    if [ ! -f "$_starship_cache" ]; then
        mkdir -p "$(dirname "$_starship_cache")"
        starship init zsh > "$_starship_cache"
    fi
    source "$_starship_cache"
fi
EOF
append_zshrc 'starship init' "Starship prompt" "$BLOCK"

# ~/.local/bin은 uv/claude/codex 네이티브 인스톨러가 .zshenv/.zprofile에 넣기도
# 하므로 .zshrc만이 아니라 셋 다 확인 — 어디든 있으면 이미 설정된 것
if grep -qE '\.local/bin' "$ZSHRC" "$HOME/.zshenv" "$HOME/.zprofile" 2>/dev/null; then
    ok "~/.local/bin PATH (already configured)"
else
    IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Local bin (native installers: claude, codex) ─────────
# Idempotent: the native installers may already add this line, so only prepend
# when it is not on PATH yet — avoids a duplicate ~/.local/bin entry.
# (no apostrophes in this block: macOS bash 3.2 miscounts quotes in $(<<EOF))
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
EOF
    append_zshrc '\.local/bin' "~/.local/bin PATH" "$BLOCK"
fi

# brew shellenv는 Homebrew 설치기가 .zprofile에 넣는 것이 표준 위치 — 거기 있으면 skip
if grep -qE 'brew shellenv' "$ZSHRC" "$HOME/.zprofile" 2>/dev/null; then
    ok "Homebrew shellenv (already configured)"
else
    IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Homebrew (Apple Silicon) ──────────────────────────────
[ -f "/opt/homebrew/bin/brew" ] && eval "$(/opt/homebrew/bin/brew shellenv)"
EOF
    append_zshrc 'brew shellenv' "Homebrew shellenv" "$BLOCK"
fi

if [ "$HAND_CONFIGURED" = 0 ]; then
    IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
EOF
    append_zshrc '\[shell\] loaded' "startup time report" "$BLOCK"
fi

# ── 7. SSH agent ──────────────────────────────────────────
# macOS는 launchd + 키체인이 자동 관리 → 별도 설정 불필요
ok "SSH agent — macOS keychain handles this automatically"

# ── Report a problem (terminal-friendly) ─────────────────
# 1) Pre-filled GitHub issue URL (OS + failed items already filled in).
# 2) gh (installed above): if present, offer to file the issue from the terminal.
if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    warn "${#FAILED[@]} item(s) failed:"
    for f in "${FAILED[@]}"; do echo -e "  ${RED}[FAILED]${NC} $f"; done

    TITLE="[install] ${#FAILED[@]} issue(s) on macOS"
    BODY="## 환경 (Environment)
- OS: macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))
- Shell: $SHELL

## 실패 항목 (Failed items)
$(printf -- '- %s\n' "${FAILED[@]}")
## 추가 상황 (Notes)
<!-- 무엇을 하다 생긴 문제인지 적어주세요 -->"

    if command -v python3 &>/dev/null; then
        enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.buffer.read().decode("utf-8")),end="")'; }
        URL="https://github.com/hd0126/dev-setup/issues/new?title=$(printf '%s' "$TITLE" | enc)&body=$(printf '%s' "$BODY" | enc)"
    else
        URL="https://github.com/hd0126/dev-setup/issues/new"
    fi
    echo ""
    echo -e "${CYAN}문제를 알려주세요 (초보 환영):${NC}"
    echo "  아래 링크를 열면 내용이 자동으로 채워집니다 (Submit만 누르면 끝):"
    echo "  $URL"

    if command -v gh &>/dev/null; then
        printf "  gh로 지금 이슈를 생성할까요? (gh 로그인 필요) [y/N] "
        read -r ans </dev/tty 2>/dev/null || ans=""
        case "$ans" in
            y|Y|yes) printf '%s' "$BODY" | gh issue create --repo hd0126/dev-setup --title "$TITLE" --body-file - \
                       && ok "이슈가 생성되었습니다. 감사합니다!" \
                       || warn "gh 제출 실패 — 위 링크로 열어주세요 ('gh auth login' 후 재시도 가능)." ;;
        esac
    fi
fi

# ── Done ──────────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${CYAN}  Done in ${ELAPSED}s${NC}"
echo -e "${CYAN}  NEXT STEP: Open a new terminal to apply${NC}"
echo -e "${CYAN}  changes, then run: cc --version${NC}"
echo -e "${GREEN}=============================================${NC}"
