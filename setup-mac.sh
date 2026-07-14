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
    # 다운로드 후 실행: `bash -c "$(curl ...)"`는 명령 치환이라 pipefail 대상이 아니고,
    # curl -f 실패 시 빈 문자열이 bash 로 넘어가 조용히 exit 0 → "설치됨" 오보고된다.
    _brew_installer="$(mktemp)"
    if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$_brew_installer"; then
        /bin/bash "$_brew_installer" || true
    else
        warn "Homebrew 설치 스크립트 다운로드 실패 — 네트워크를 확인하세요."
    fi
    rm -f "$_brew_installer"
    # Apple Silicon / Intel PATH 설정
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    # 설치 성공을 실제로 검증 — 다운로드/실행 실패를 성공으로 보고하지 않도록.
    if command -v brew &>/dev/null; then
        ok "Homebrew"
    else
        fail "Homebrew (설치 실패 — 위 로그 확인)"
    fi
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

# 쾌적함 플러스 (전부 시작속도 영향 미미 또는 0)
install_brew zsh-autosuggestions        # 히스토리 기반 회색 자동제안
install_brew zsh-syntax-highlighting    # 입력 중 명령 유효/오타 색상
install_brew zsh-history-substring-search # ↑↓ 부분일치 히스토리 검색
install_brew eza                        # ls 대체 (아이콘·git 상태)
install_brew bat                        # cat 대체 (문법 하이라이트)
install_brew fd                         # find 대체 (fzf Ctrl+T 가속)
install_brew git-delta                  # git diff 하이라이트
install_brew tealdeer                   # tldr — 예시 위주 명령어 도움말

# ── 2b. Nerd Font (Starship·eza 아이콘용) ─────────────────
if brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
    ok "JetBrainsMono Nerd Font (already installed)"
else
    info "Installing JetBrainsMono Nerd Font..."
    if brew install --cask font-jetbrains-mono-nerd-font; then
        ok "JetBrainsMono Nerd Font — 터미널 앱 설정에서 폰트를 'JetBrainsMono Nerd Font'로 변경하세요"
    else
        fail "JetBrainsMono Nerd Font"
    fi
fi

# ── 3. Node.js LTS (Homebrew) ─────────────────────────────
# `brew install node`는 Current 라인(LTS 아님)을 설치한다 — Linux(NodeSource
# setup_lts.x)와 동일하게 최신 LTS 메이저를 동적으로 판별해 node@<major>를 설치.
# 특정 메이저 하드코딩 금지: LTS가 바뀔 때마다 스크립트가 낡는다.
node_lts_major() {
    curl -fsSL --max-time 10 https://nodejs.org/dist/index.json 2>/dev/null |
        python3 -c 'import sys,json;vs=[v for v in json.load(sys.stdin) if v.get("lts")];print(max(int(v["version"][1:].split(".")[0]) for v in vs) if vs else "")' 2>/dev/null
}
if ! command -v node &>/dev/null; then
    LTS_MAJOR="$(node_lts_major)" || LTS_MAJOR=""
    if [ -n "$LTS_MAJOR" ] && brew info "node@$LTS_MAJOR" &>/dev/null; then
        install_brew "node@$LTS_MAJOR"
        # node@<major>는 keg-only — node/npm이 PATH에 잡히도록 링크
        brew link --overwrite --force "node@$LTS_MAJOR" &>/dev/null \
            || warn "node@$LTS_MAJOR 링크 실패 — PATH에 $(brew --prefix "node@$LTS_MAJOR" 2>/dev/null)/bin 추가 필요"
    else
        warn "Node LTS 버전 판별 실패(네트워크/포뮬러 없음) — brew 기본 node(Current)로 대체"
        install_brew node
    fi
else
    NODE_V=$(node --version)
    if [ "$(node -p 'process.release.lts ? "y" : "n"' 2>/dev/null)" != "y" ]; then
        warn "기존 Node.js $NODE_V 는 LTS가 아닙니다(Current 또는 EOL) — 기존 설치 존중, 계속 진행"
        warn "  LTS 전환: brew install node@<LTS메이저> && brew link --overwrite --force node@<LTS메이저>"
    fi
    ok "Node.js (already installed: $NODE_V)"
fi

# ── 5. npm global packages ────────────────────────────────
install_npm() {
    local pkg="$1"
    local installed latest
    # grep -E only: macOS BSD grep has no -P (PCRE), which made this always
    # come back empty and reinstall every package on every run
    installed=$(npm list -g --depth=0 2>/dev/null | grep -F "$pkg@" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1)
    # `|| latest=""` 가드 필수: 단독 할당문이라 npm view 실패(오프라인·레지스트리
    # 오류)가 set -e로 스크립트 전체를 무메시지 종료시킨다 — 이후의 셸 설정
    # 섹션과 실패 리포트까지 통째로 건너뛰게 됨.
    latest=$(npm view "$pkg" version 2>/dev/null) || latest=""
    if [ -z "$installed" ]; then
        info "Installing $pkg..."
        npm install -g --no-fund --loglevel=error "$pkg" && ok "$pkg" || fail "$pkg"
    elif [ -z "$latest" ]; then
        warn "$pkg — 최신 버전 확인 실패(네트워크?), 설치된 $installed 유지"
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
    local name="$1" url="$2" sh="${3:-bash}" cmd="$4"
    # Native builds self-update in the background, so an existing install is
    # enough — skip the re-download (it is big, and painful on flaky networks).
    # Check the native launcher path specifically, NOT `command -v`: on a
    # machine that still has the npm version, command -v would find that and
    # skip the migration to native.
    if [ -n "$cmd" ] && [ -x "$HOME/.local/bin/$cmd" ]; then
        ok "$name (already installed: $("$HOME/.local/bin/$cmd" --version 2>/dev/null | head -1))"
        return 0
    fi
    local tmp; tmp="$(mktemp)"
    info "Installing $name (native installer)..."
    # Download first, THEN run: piping `curl | sh` hides a failed download
    # (sh exits 0 on empty stdin), so a 404/network error would falsely report OK.
    if curl -fsSL "$url" -o "$tmp" && "$sh" "$tmp"; then ok "$name"; else fail "$name"; fi
    rm -f "$tmp"
}

install_native "Claude Code"    "https://claude.ai/install.sh"         bash claude
install_native "codex (OpenAI)" "https://chatgpt.com/codex/install.sh" sh   codex

if command -v npm &>/dev/null; then
    install_npm "@google/gemini-cli"
    install_npm "oh-my-claude-sisyphus"
    install_npm "oh-my-codex"
else
    warn "npm not found — skipping gemini-cli/omc/omx. Install Node.js first, then re-run."
fi

# ── 5b. git-delta를 git pager로 (기존 설정 있으면 건드리지 않음) ──
if command -v delta &>/dev/null; then
    if git config --global core.pager &>/dev/null; then
        ok "git pager (기존 설정 유지)"
    else
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        ok "git-delta → git diff 하이라이트 적용"
    fi
fi

# ── 5c. tealdeer 캐시 초기화 (첫 tldr 실행 대비) ──────────
if command -v tldr &>/dev/null && [ ! -d "${HOME}/Library/Caches/tealdeer" ]; then
    tldr --update &>/dev/null || warn "tldr 캐시 다운로드 실패 — 나중에 'tldr --update' 실행"
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
    local signature="$1" label="$2" block="$3" tail="${4:-}"
    if grep -qE "$signature" "$ZSHRC" 2>/dev/null; then
        ok "$label (already in .zshrc — 기존 설정 존중, 건너뜀)"
        return 0
    fi
    # zsh-syntax-highlighting 블록은 반드시 파일 끝부분이어야 한다. 부분 재실행으로
    # 새 기능 블록이 그 뒤에 붙지 않도록, 우리 syntax 블록이 이미 있으면 그 앞에
    # 삽입한다. (tail 블록 = syntax/substring/타이머 리포트는 끝에 그대로 append)
    local sh_marker='# ── zsh-syntax-highlighting'
    if [ -z "$tail" ] && grep -qF "$sh_marker" "$ZSHRC" 2>/dev/null; then
        local tmpb tmpf
        tmpb="$(mktemp)"; tmpf="$(mktemp)"
        printf '%s\n' "$block" > "$tmpb"
        awk -v m="$sh_marker" -v bf="$tmpb" '
            index($0, m) == 1 && !done { while ((getline l < bf) > 0) print l; print ""; done=1 }
            { print }
        ' "$ZSHRC" > "$tmpf" && mv "$tmpf" "$ZSHRC"
        rm -f "$tmpb"
        ok "$label → .zshrc (syntax-highlighting 앞에 삽입)"
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
# cc는 넓게 매칭: 사용자가 alias cc='clang' 같은 개인 alias를 갖고 있으면
# 가로채지 않고 존중한다 (claude 명령은 그대로 쓸 수 있음)
append_zshrc '^[^#]*alias cc=' "Claude Code shortcuts (cc/ccc/ccr)" "$BLOCK"

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

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zsh-autosuggestions (히스토리 기반 회색 자동제안, →로 수락) ──
# Apple Silicon(/opt/homebrew)과 Intel(/usr/local) 모두 지원 — 환경변수에
# 의존하면 HOMEBREW_PREFIX 미설정 셸(Intel 비로그인 등)에서 조용히 미로드됨
if [ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
elif [ -f /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
EOF
append_zshrc 'zsh-autosuggestions' "zsh-autosuggestions" "$BLOCK"

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── eza (ls 대체: 아이콘·git 상태 — Nerd Font 필요) ───────
if command -v eza &>/dev/null; then
    alias ll='eza -l --icons'
    alias la='eza -la --icons'
    alias lt='eza --tree --icons'
fi
EOF
append_zshrc '^[^#]*alias ll=.?eza' "eza aliases (ll/la/lt)" "$BLOCK"

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── bat (cat 대체: 문법 하이라이트·줄번호) ─────────────────
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
fi
EOF
append_zshrc '^[^#]*alias cat=.?bat' "bat alias (cat)" "$BLOCK"

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fd + fzf 연동 (Ctrl+T 파일검색 가속, .gitignore 존중) ──
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
EOF
append_zshrc 'FZF_DEFAULT_COMMAND' "fd + fzf integration" "$BLOCK"

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
# ── Homebrew (Apple Silicon: /opt/homebrew, Intel: /usr/local) ──
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
EOF
    append_zshrc 'brew shellenv' "Homebrew shellenv" "$BLOCK"
fi

# Homebrew python@3.12는 무버전 명령(python3/pip3)을 기본 bin이 아닌
# libexec/bin에만 둔다 — PATH에 없으면 CLT의 /usr/bin/python3가 잡힌다.
# autosuggestions 블록처럼 양쪽 prefix를 하드코딩(브루 셸env 로드 순서 무관).
IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Homebrew Python (python3/pip3 → python@3.12) ─────────
if [ -d /opt/homebrew/opt/python@3.12/libexec/bin ]; then
    export PATH="/opt/homebrew/opt/python@3.12/libexec/bin:$PATH"
elif [ -d /usr/local/opt/python@3.12/libexec/bin ]; then
    export PATH="/usr/local/opt/python@3.12/libexec/bin:$PATH"
fi
EOF
append_zshrc 'python@3\.12/libexec' "Homebrew Python PATH (python3/pip3)" "$BLOCK"

# syntax-highlighting은 모든 위젯 로드 후 마지막에 source해야 하고,
# history-substring-search는 그보다도 뒤여야 함 (플러그인 공식 권장 순서)
IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zsh-syntax-highlighting (명령 유효/오타 색상 — 반드시 끝부분) ──
if [ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
EOF
append_zshrc 'zsh-syntax-highlighting' "zsh-syntax-highlighting" "$BLOCK" tail

IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zsh-history-substring-search (↑↓ 부분일치 검색) ───────
if [ -f /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    source /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh
elif [ -f /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    source /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh
fi
if type history-substring-search-up &>/dev/null; then
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi
EOF
append_zshrc 'history-substring-search' "zsh-history-substring-search" "$BLOCK" tail

if [ "$HAND_CONFIGURED" = 0 ]; then
    IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
EOF
    append_zshrc '\[shell\] loaded' "startup time report" "$BLOCK" tail
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
        printf "  gh로 지금 이슈를 생성할까요? [y/N] "
        read -r ans </dev/tty 2>/dev/null || ans=""
        case "$ans" in
            y|Y|yes)
                if ! gh auth status &>/dev/null; then
                    echo "  GitHub 로그인이 필요합니다 — 브라우저 안내를 따라주세요 (무료 계정이면 충분)."
                    gh auth login --hostname github.com --web </dev/tty || true
                fi
                if gh auth status &>/dev/null; then
                    printf '%s' "$BODY" | gh issue create --repo hd0126/dev-setup --title "$TITLE" --body-file - \
                        && ok "이슈가 생성되었습니다. 감사합니다!" \
                        || warn "gh 제출 실패 — 위 링크로 직접 열어주세요 (클릭 → Submit)."
                else
                    warn "로그인이 완료되지 않았습니다 — 위 링크로 직접 열어주세요 (클릭 → Submit)."
                fi ;;
        esac
    fi
fi

# ── Star (optional) ───────────────────────────────────────
# 전부 성공했을 때만 제안. 이미 star했으면 조용히 스킵, 미로그인이면 링크만.
if [ ${#FAILED[@]} -eq 0 ]; then
    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        if ! gh api user/starred/hd0126/dev-setup --silent 2>/dev/null; then
            echo ""
            printf "이 스크립트가 도움이 됐다면 ⭐ star로 응원해주세요! 지금 누를까요? [y/N] "
            read -r ans </dev/tty 2>/dev/null || ans=""
            case "$ans" in
                y|Y|yes) gh api -X PUT user/starred/hd0126/dev-setup --silent 2>/dev/null \
                           && ok "Star 감사합니다! ⭐" \
                           || warn "star 실패 — https://github.com/hd0126/dev-setup 에서 직접 눌러주세요." ;;
            esac
        fi
    else
        echo ""
        echo -e "${CYAN}도움이 됐다면 ⭐: https://github.com/hd0126/dev-setup${NC}"
    fi
fi

# ── Done ──────────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${CYAN}  Done in ${ELAPSED}s${NC}"
echo -e "${CYAN}  NEXT STEP: Open a new terminal to apply${NC}"
echo -e "${CYAN}  changes, then run: claude --version${NC}"
echo -e "${CYAN}  아이콘이 □로 깨지면: 터미널 설정에서 폰트를${NC}"
echo -e "${CYAN}  'JetBrainsMono Nerd Font'로 변경하세요${NC}"
echo -e "${GREEN}=============================================${NC}"

# 실패 항목이 있으면 비정상 종료 — CI·프로비저닝 도구가 실패를 감지할 수 있도록
[ ${#FAILED[@]} -eq 0 ] || exit 1
