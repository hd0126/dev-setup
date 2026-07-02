#!/usr/bin/env bash
# Linux (Ubuntu/Debian) setup script
# Usage: bash setup-linux.sh

set -e
START_TIME=$SECONDS

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[..] $1${NC}"; }
warn() { echo -e "${YELLOW}[!!] $1${NC}"; }
FAILED=()
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED+=("$1"); }

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

# ── 4. Node.js LTS (NodeSource) ───────────────────────────
if ! command -v node &>/dev/null; then
    info "Installing Node.js LTS via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y -q nodejs && ok "Node.js LTS" || fail "Node.js LTS"
else
    ok "Node.js (already installed: $(node --version))"
fi

# npm 전역 패키지를 sudo 없이 설치하도록 prefix 설정 (~/.npm-global)
if command -v npm &>/dev/null; then
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
fi

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

# ── 6b. uv (Python package manager) ───────────────────────
if ! command -v uv &>/dev/null; then
    info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh && ok "uv" || fail "uv"
    export PATH="$HOME/.local/bin:$PATH"
else
    ok "uv (already installed)"
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

# Claude Code and codex ship official native installers (standalone binaries
# with background auto-update) — the vendor-recommended path. Install those
# natively, independent of npm; gemini-cli / omc / omx stay on npm.
# Both installers drop binaries in ~/.local/bin, already on PATH (see uv above).
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

# Re-run safe, per-feature: append each block only when its feature isn't
# already in the config file (signature grep). The old all-or-nothing marker
# check re-appended the WHOLE snippet on machines whose rc file was configured
# by hand (no marker) — duplicating aliases and inits. Hand-written
# equivalents (e.g. plain `eval "$(starship init zsh)"`) count as configured
# and are left untouched.
append_cfg() {
    local cfg="$1" signature="$2" label="$3" block="$4"
    if grep -qE "$signature" "$cfg" 2>/dev/null; then
        ok "$label (already in $cfg)"
    else
        printf '\n%s\n' "$block" >> "$cfg"
        ok "$label → $cfg"
    fi
}

for cfg in "${SHELL_CONFIGS[@]}"; do
    # Startup timer must PRECEDE the feature blocks it measures, so it only
    # makes sense when they're appended fresh in the same run. On a config
    # that already has any of them (hand-configured), skip it — appended at
    # the end it would just print a meaningless "loaded in 0ms" every shell.
    hand_configured=0
    if grep -qE 'alias cc=|zoxide init|fzf --(zsh|bash)|starship init' "$cfg" 2>/dev/null; then
        hand_configured=1
    fi

    if [[ "$cfg" == *".zshrc" ]]; then

        if [ "$hand_configured" = 0 ]; then
            IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Shell startup timer ───────────────────────────────────
zmodload zsh/datetime
_shell_start=$EPOCHREALTIME
EOF
            append_cfg "$cfg" '_shell_start=\$EPOCHREALTIME' "startup timer" "$BLOCK"
        fi
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Claude Code shortcuts ──────────────────────────────────
alias cc='claude --dangerously-skip-permissions'
alias ccc='cc --continue'
alias ccr='cc --resume'
EOF
        append_cfg "$cfg" 'alias cc=' "Claude Code shortcuts (cc/ccc/ccr)" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zoxide ────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh --cmd z)"
fi
EOF
        append_cfg "$cfg" 'zoxide init' "zoxide" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fzf ───────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    source <(fzf --zsh 2>/dev/null || true)
fi
EOF
        append_cfg "$cfg" 'fzf --zsh' "fzf" "$BLOCK"
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
        append_cfg "$cfg" 'starship init' "Starship prompt" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── npm global bin (no-sudo prefix) ──────────────────────
case ":$PATH:" in *":$HOME/.npm-global/bin:"*) ;; *) export PATH="$HOME/.npm-global/bin:$PATH" ;; esac
EOF
        append_cfg "$cfg" '\.npm-global' "npm global bin PATH" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── uv / native installers (~/.local/bin) ────────────────
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
EOF
        append_cfg "$cfg" '\.local/bin' "~/.local/bin PATH (uv, native installers)" "$BLOCK"
        if [ "$hand_configured" = 0 ]; then
            IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
EOF
            append_cfg "$cfg" '\[shell\] loaded' "startup time report" "$BLOCK"
        fi

    else

        if [ "$hand_configured" = 0 ]; then
            IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Shell startup timer ───────────────────────────────────
_shell_start=$(date +%s%3N)
EOF
            append_cfg "$cfg" '_shell_start=\$\(date' "startup timer" "$BLOCK"
        fi
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Claude Code shortcuts ──────────────────────────────────
alias cc='claude --dangerously-skip-permissions'
alias ccc='cc --continue'
alias ccr='cc --resume'
EOF
        append_cfg "$cfg" 'alias cc=' "Claude Code shortcuts (cc/ccc/ccr)" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zoxide ────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash --cmd z)"
fi
EOF
        append_cfg "$cfg" 'zoxide init' "zoxide" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fzf ───────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    eval "$(fzf --bash 2>/dev/null || true)"
fi
EOF
        append_cfg "$cfg" 'fzf --bash' "fzf" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Starship prompt (cached) ──────────────────────────────
if command -v starship &>/dev/null; then
    _starship_cache="${XDG_CACHE_HOME:-$HOME/.cache}/starship_init_bash.sh"
    if [ ! -f "$_starship_cache" ]; then
        mkdir -p "$(dirname "$_starship_cache")"
        starship init bash > "$_starship_cache"
    fi
    source "$_starship_cache"
fi
EOF
        append_cfg "$cfg" 'starship init' "Starship prompt" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── npm global bin (no-sudo prefix) ──────────────────────
case ":$PATH:" in *":$HOME/.npm-global/bin:"*) ;; *) export PATH="$HOME/.npm-global/bin:$PATH" ;; esac
EOF
        append_cfg "$cfg" '\.npm-global' "npm global bin PATH" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── uv / native installers (~/.local/bin) ────────────────
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
EOF
        append_cfg "$cfg" '\.local/bin' "~/.local/bin PATH (uv, native installers)" "$BLOCK"
        if [ "$hand_configured" = 0 ]; then
            IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %dms\033[0m\n' "$(( $(date +%s%3N) - _shell_start ))"
    unset _shell_start
fi
EOF
            append_cfg "$cfg" '\[shell\] loaded' "startup time report" "$BLOCK"
        fi

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

# ── Report a problem (terminal-friendly) ─────────────────
# 1) Pre-filled GitHub issue URL (OS + failed items already filled in).
# 2) gh (installed above): if present, offer to file the issue from the terminal.
if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    warn "${#FAILED[@]} item(s) failed:"
    for f in "${FAILED[@]}"; do echo -e "  ${RED}[FAILED]${NC} $f"; done

    DISTRO=$(grep -oP '(?<=PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null || uname -sr)
    TITLE="[install] ${#FAILED[@]} issue(s) on Linux"
    BODY="## 환경 (Environment)
- OS: ${DISTRO} ($(uname -m))
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
