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

# 배포판 버전에 따라 apt에 없을 수 있는 패키지 — 없으면 경고만 하고 계속.
# apt-cache로 '저장소에 없음'과 '설치 실패'를 구분(락 대기·네트워크 오류를
# '없음'으로 오진하지 않음). 설치 출력은 숨기지 않는다 — sudo 비밀번호
# 프롬프트까지 숨겨지면 멈춘 것처럼 보이기 때문.
install_apt_opt() {
    if dpkg -s "$1" &>/dev/null; then
        ok "$1 (already installed)"
    elif ! apt-cache show "$1" &>/dev/null; then
        warn "$1 — apt 저장소에 없음(배포판 버전에 따라 다름), 건너뜀"
    else
        info "Installing $1..."
        sudo apt-get install -y -q "$1" && ok "$1" || fail "$1"
    fi
}

# 쾌적함 플러스 (전부 시작속도 영향 미미 또는 0)
install_apt_opt zsh-autosuggestions     # 히스토리 기반 회색 자동제안 (zsh)
install_apt_opt zsh-syntax-highlighting # 입력 중 명령 유효/오타 색상 (zsh)
install_apt_opt zsh-history-substring-search # ↑↓ 부분일치 히스토리 검색 (zsh)
install_apt_opt eza                     # ls 대체 (Ubuntu 24.04+)
install_apt_opt bat                     # cat 대체 — Ubuntu에선 batcat 명령
install_apt_opt fd-find                 # find 대체 — Ubuntu에선 fdfind 명령
install_apt_opt git-delta               # git diff 하이라이트
install_apt_opt tealdeer                # tldr — 예시 위주 명령어 도움말

# ── 2. GitHub CLI ─────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    info "Installing GitHub CLI..."
    # 국소 pipefail: curl 실패 시 빈/손상 keyring 이 디스크에 남아 이후 apt-get update 를
    # 영구히 깨뜨리는 것을 막는다 (dd 는 빈 stdin 에도 exit 0 이라 set -e 만으론 못 잡음).
    if ( set -o pipefail; curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg ); then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -q && sudo apt-get install -y -q gh && ok "GitHub CLI" || fail "GitHub CLI"
    else
        sudo rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
        fail "GitHub CLI (keyring 다운로드 실패 — 네트워크 확인)"
    fi
else
    ok "GitHub CLI (already installed)"
fi

# ── 4. Node.js LTS (NodeSource) ───────────────────────────
if ! command -v node &>/dev/null; then
    info "Installing Node.js LTS via NodeSource..."
    # 국소 pipefail: curl 실패가 sudo bash 의 exit 0 뒤에 숨지 않도록.
    if ( set -o pipefail; curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - ); then
        sudo apt-get install -y -q nodejs && ok "Node.js LTS" || fail "Node.js LTS"
    else
        fail "Node.js LTS (NodeSource 설정 다운로드 실패 — 네트워크 확인)"
    fi
else
    ok "Node.js (already installed: $(node --version))"
fi

# npm 전역 패키지를 sudo 없이 설치하도록 prefix 설정 (~/.npm-global)
# 단, prefix가 시스템 경로(/usr 등, sudo 필요)일 때만 변경 — nvm 등
# 사용자가 이미 쓰기 가능한 prefix를 쓰고 있으면 건드리지 않는다
# (nvm은 prefix를 바꾸면 동작이 깨진다).
if command -v npm &>/dev/null; then
    cur_prefix=$(npm config get prefix 2>/dev/null || echo "")
    case "$cur_prefix" in
        /usr|/usr/local)
            mkdir -p "$HOME/.npm-global"
            npm config set prefix "$HOME/.npm-global"
            export PATH="$HOME/.npm-global/bin:$PATH"
            ok "npm prefix → ~/.npm-global (sudo 없이 npm install -g)"
            ;;
        "$HOME/.npm-global")
            export PATH="$HOME/.npm-global/bin:$PATH"
            ok "npm prefix (~/.npm-global — already configured)"
            ;;
        *)
            ok "npm prefix (기존 설정 유지: ${cur_prefix:-unknown})"
            ;;
    esac
fi

# ── 5. Starship ───────────────────────────────────────────
if ! command -v starship &>/dev/null; then
    info "Installing Starship..."
    if ( set -o pipefail; curl -fsSL https://starship.rs/install.sh | sh -s -- --yes ); then ok "Starship"; else fail "Starship"; fi
else
    ok "Starship (already installed)"
fi

# ── 6. zoxide ─────────────────────────────────────────────
if ! command -v zoxide &>/dev/null; then
    info "Installing zoxide..."
    if ( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash ); then ok "zoxide"; else fail "zoxide"; fi
else
    ok "zoxide (already installed)"
fi

# ── 6b. uv (Python package manager) ───────────────────────
if ! command -v uv &>/dev/null; then
    info "Installing uv..."
    if ( set -o pipefail; curl -LsSf https://astral.sh/uv/install.sh | sh ); then ok "uv"; else fail "uv"; fi
    export PATH="$HOME/.local/bin:$PATH"
else
    ok "uv (already installed)"
fi

# ── 7. npm global packages ────────────────────────────────
install_npm() {
    local pkg="$1"
    local installed latest
    # grep -E only (BSD/GNU 공통) — -P는 macOS BSD grep에 없음
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
# Both installers drop binaries in ~/.local/bin, already on PATH (see uv above).
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

# ── 7b. git-delta를 git pager로 (기존 설정 있으면 건드리지 않음) ──
if command -v delta &>/dev/null; then
    if git config --global core.pager &>/dev/null; then
        ok "git pager (기존 설정 유지)"
    else
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        ok "git-delta → git diff 하이라이트 적용"
    fi
fi

# ── 7c. tealdeer 캐시 초기화 (첫 tldr 실행 대비) ──────────
if command -v tldr &>/dev/null && [ ! -d "${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer" ]; then
    tldr --update &>/dev/null || warn "tldr 캐시 다운로드 실패 — 나중에 'tldr --update' 실행"
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
    local cfg="$1" signature="$2" label="$3" block="$4" tail="${5:-}"
    if grep -qE "$signature" "$cfg" 2>/dev/null; then
        ok "$label (already in $cfg — 기존 설정 존중, 건너뜀)"
        return 0
    fi
    # zsh-syntax-highlighting 블록은 반드시 파일 끝부분이어야 한다. 부분 재실행으로
    # 새 기능 블록이 그 뒤에 붙지 않도록, 우리 syntax 블록이 이미 있으면 그 앞에
    # 삽입한다. (tail 블록 = syntax/타이머 리포트는 끝에 그대로 append)
    local sh_marker='# ── zsh-syntax-highlighting'
    if [ -z "$tail" ] && grep -qF "$sh_marker" "$cfg" 2>/dev/null; then
        local tmpb tmpf
        tmpb="$(mktemp)"; tmpf="$(mktemp)"
        printf '%s\n' "$block" > "$tmpb"
        awk -v m="$sh_marker" -v bf="$tmpb" '
            index($0, m) == 1 && !done { while ((getline l < bf) > 0) print l; print ""; done=1 }
            { print }
        ' "$cfg" > "$tmpf" && mv "$tmpf" "$cfg"
        rm -f "$tmpb"
        ok "$label → $cfg (syntax-highlighting 앞에 삽입)"
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
        # cc는 넓게 매칭: 사용자의 개인 alias cc(예: clang)를 가로채지 않고 존중
        append_cfg "$cfg" '^[^#]*alias cc=' "Claude Code shortcuts (cc/ccc/ccr)" "$BLOCK"
        # PATH 블록은 이를 참조하는 도구 init(zoxide 등)보다 먼저 와야 한다
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
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zoxide ────────────────────────────────────────────────
# zoxide는 ~/.local/bin에 설치됨 — PATH 반영 전이라도 동작하도록 보강
if [ -x "$HOME/.local/bin/zoxide" ] || command -v zoxide &>/dev/null; then
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    eval "$(zoxide init zsh --cmd z)"
fi
EOF
        append_cfg "$cfg" 'zoxide init' "zoxide" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fzf (Ctrl+R 히스토리 · Ctrl+T 파일 검색) ──────────────
if command -v fzf &>/dev/null; then
    if fzf --zsh &>/dev/null; then
        source <(fzf --zsh)
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        # 구버전 fzf(<0.48, apt 기본)는 --zsh 미지원 → 배포판 키바인딩 파일 사용
        source /usr/share/doc/fzf/examples/key-bindings.zsh
    fi
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
# ── zsh-autosuggestions (히스토리 기반 회색 자동제안, →로 수락) ──
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
EOF
        append_cfg "$cfg" 'zsh-autosuggestions' "zsh-autosuggestions" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── eza (ls 대체 — Nerd Font 설치 시 --icons 옵션 추가 가능) ──
if command -v eza &>/dev/null; then
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
fi
EOF
        append_cfg "$cfg" '^[^#]*alias ll=.?eza' "eza aliases (ll/la/lt)" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── bat (cat 대체: 문법 하이라이트) — Ubuntu는 batcat ─────
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
elif command -v batcat &>/dev/null; then
    alias cat='batcat --paging=never'
fi
EOF
        append_cfg "$cfg" '^[^#]*alias cat=.?bat' "bat alias (cat)" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fd + fzf 연동 (Ctrl+T 파일검색 가속) — Ubuntu는 fdfind ──
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
elif command -v fdfind &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
EOF
        append_cfg "$cfg" 'FZF_DEFAULT_COMMAND' "fd + fzf integration" "$BLOCK"
        # syntax-highlighting은 모든 위젯 로드 후 마지막에 source (플러그인 공식 권장)
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zsh-syntax-highlighting (명령 유효/오타 색상 — 반드시 끝부분) ──
if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
EOF
        append_cfg "$cfg" 'zsh-syntax-highlighting' "zsh-syntax-highlighting" "$BLOCK" tail
        # history-substring-search는 syntax-highlighting보다도 뒤여야 함 (플러그인 공식 권장 순서)
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zsh-history-substring-search (↑↓ 부분일치 검색 — 반드시 syntax-highlighting 뒤) ──
if [ -f /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    source /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh
fi
if type history-substring-search-up &>/dev/null; then
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi
EOF
        append_cfg "$cfg" 'history-substring-search' "zsh-history-substring-search" "$BLOCK" tail
        if [ "$hand_configured" = 0 ]; then
            IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
EOF
            append_cfg "$cfg" '\[shell\] loaded' "startup time report" "$BLOCK" tail
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
        # cc는 넓게 매칭: 사용자의 개인 alias cc(예: clang)를 가로채지 않고 존중
        append_cfg "$cfg" '^[^#]*alias cc=' "Claude Code shortcuts (cc/ccc/ccr)" "$BLOCK"
        # PATH 블록은 이를 참조하는 도구 init(zoxide 등)보다 먼저 와야 한다
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
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── zoxide ────────────────────────────────────────────────
# zoxide는 ~/.local/bin에 설치됨 — PATH 반영 전이라도 동작하도록 보강
if [ -x "$HOME/.local/bin/zoxide" ] || command -v zoxide &>/dev/null; then
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    eval "$(zoxide init bash --cmd z)"
fi
EOF
        append_cfg "$cfg" 'zoxide init' "zoxide" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fzf (Ctrl+R 히스토리 · Ctrl+T 파일 검색) ──────────────
if command -v fzf &>/dev/null; then
    if fzf --bash &>/dev/null; then
        eval "$(fzf --bash)"
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        # 구버전 fzf(<0.48, apt 기본)는 --bash 미지원 → 배포판 키바인딩 파일 사용
        source /usr/share/doc/fzf/examples/key-bindings.bash
    fi
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
# ── eza (ls 대체 — Nerd Font 설치 시 --icons 옵션 추가 가능) ──
if command -v eza &>/dev/null; then
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
fi
EOF
        append_cfg "$cfg" '^[^#]*alias ll=.?eza' "eza aliases (ll/la/lt)" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── bat (cat 대체: 문법 하이라이트) — Ubuntu는 batcat ─────
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
elif command -v batcat &>/dev/null; then
    alias cat='batcat --paging=never'
fi
EOF
        append_cfg "$cfg" '^[^#]*alias cat=.?bat' "bat alias (cat)" "$BLOCK"
        IFS= read -r -d '' BLOCK <<'EOF' || true
# ── fd + fzf 연동 (Ctrl+T 파일검색 가속) — Ubuntu는 fdfind ──
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
elif command -v fdfind &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
EOF
        append_cfg "$cfg" 'FZF_DEFAULT_COMMAND' "fd + fzf integration" "$BLOCK"
        if [ "$hand_configured" = 0 ]; then
            IFS= read -r -d '' BLOCK <<'EOF' || true
# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %dms\033[0m\n' "$(( $(date +%s%3N) - _shell_start ))"
    unset _shell_start
fi
EOF
            append_cfg "$cfg" '\[shell\] loaded' "startup time report" "$BLOCK" tail
        fi

    fi
done

# ── 9. SSH agent ──────────────────────────────────────────
# macOS와 달리 Linux는 자동 관리 안 되므로 .bashrc/.zshrc에 추가
SSH_AGENT_SNIPPET=$(cat <<'SSHSNIPPET'

# ── SSH agent ─────────────────────────────────────────────
# 셸마다 에이전트를 새로 띄우지 않고 ~/.ssh/agent.env로 재사용(고아 프로세스 방지).
# 개인키가 있을 때만 에이전트를 시작하고, known_hosts류·authorized_keys는 제외.
if [ -z "$SSH_AUTH_SOCK" ] && [ -d "$HOME/.ssh" ]; then
    [ -f "$HOME/.ssh/agent.env" ] && . "$HOME/.ssh/agent.env" >/dev/null
    if [ -z "$SSH_AUTH_SOCK" ] || [ -z "$SSH_AGENT_PID" ] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
        _ssh_key=$(find "$HOME/.ssh" -maxdepth 1 -type f \
            ! -name "*.pub" ! -name "known_hosts*" ! -name "authorized_keys" \
            ! -name "config" ! -name "agent.env" ! -name "*.old" 2>/dev/null | head -1)
        if [ -n "$_ssh_key" ]; then
            ssh-agent -s > "$HOME/.ssh/agent.env" 2>/dev/null
            chmod 600 "$HOME/.ssh/agent.env" 2>/dev/null
            . "$HOME/.ssh/agent.env" >/dev/null
            ssh-add "$_ssh_key" 2>/dev/null
        fi
        unset _ssh_key
    fi
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

    # POSIX-safe (grep -P는 BSD grep에 없고, 여기선 서브셸 sourcing이 가장 견고)
    DISTRO=$( (. /etc/os-release 2>/dev/null && printf '%s' "$PRETTY_NAME") || uname -sr)
    [ -n "$DISTRO" ] || DISTRO=$(uname -sr)
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
echo -e "${GREEN}=============================================${NC}"
