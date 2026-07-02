# PowerShell Profile & Dev Environment Setup

> 🐛 **문제가 생겼나요?** → **[이슈 열기](https://github.com/hd0126/dev-setup/issues/new/choose)** (운영체제와 에러 메시지만 적으면 됩니다 — 초보 환영!)
>
> ⭐ **도움이 됐다면** → 이 페이지 **우측 상단 Star ⭐** 를 눌러주세요!
>
> 🤝 직접 고칠 수 있다면 **[Pull Request](https://github.com/hd0126/dev-setup/pulls)** 도 환영합니다.

## 목차

- [처음 설치 (신규)](#처음-설치-신규)
  - [🪟 Windows](#-windows)
  - [🐧 Linux / 🍎 macOS](#-linux-ubuntudebian---macos)
- [설치 확인](#설치-확인)
- [설치 후 자동 적용되는 설정](#설치-후-자동-적용되는-설정)
  - [🪟 Windows (PowerShell)](#-windows-powershell)
  - [🐧 Linux / WSL (bash/zsh)](#-linux--wsl-bashzsh)
  - [🍎 macOS (zsh)](#-macos-zsh)
- [이미 설치된 경우 (설정만 추가)](#이미-설치된-경우-설정만-추가)
  - [🪟 Windows (PowerShell)](#-windows-powershell-1)
  - [🐧 bash 사용자](#-bash-사용자)
  - [🐧🍎 zsh 사용자 (Linux / WSL · macOS)](#-zsh-사용자-linux--wsl--macos)
- [설치 도구 소개](#설치-도구-소개)
  - [⚡ PowerShell 7](#-powershell-7)
  - [🚀 Starship](#-starship)
  - [📁 zoxide](#-zoxide)
  - [🔍 fzf](#-fzf)
  - [🔤 JetBrainsMono Nerd Font](#-jetbrainsmono-nerd-font)
  - [🔎 ripgrep](#-ripgrep)
  - [✨ 쾌적함 플러스 도구](#-쾌적함-플러스-도구)
  - [🤖 Claude Code](#-claude-code)
  - [🟩 Node.js LTS](#-nodejs-lts)
  - [🐍 Python 3.12](#-python-312)
  - [⚡ uv](#-uv)
  - [🐙 Git](#-git)
  - [🐱 GitHub CLI](#-github-cli)
  - [🔵 Codex CLI](#-codex-cli)
  - [💎 Gemini CLI](#-gemini-cli-googlegemini-cli)
  - [🔗 oh-my-codex](#-oh-my-codex-omx)
  - [🧩 oh-my-claude-sisyphus](#-oh-my-claude-sisyphus-omc)
- [Claude Code 플러그인](#claude-code-플러그인-로그인-후-수동-실행)
- [단축키 / 명령어](#단축키--명령어)
- [프로필 캐시 관리](#프로필-캐시-관리)
- [파일 수정 후 업데이트](#파일-수정-후-업데이트)

---

## 처음 설치 (신규)

### 🪟 Windows

PowerShell(관리자)에서 한 줄 실행:

```powershell
irm https://raw.githubusercontent.com/hd0126/dev-setup/main/install.ps1 | iex
```

자동으로 처리합니다:
- PowerShell 7, Starship, zoxide, fzf, ripgrep, Node.js, Git, GitHub CLI, Python 3.12, uv 설치 (선택 가능)
- JetBrainsMono Nerd Font 설치 + Windows Terminal 폰트 자동 설정 (선택 가능)
- Claude Code (Anthropic 네이티브 인스톨러, 백그라운드 자동 업데이트), codex (OpenAI 네이티브 인스톨러, Node 불필요), @google/gemini-cli, oh-my-codex(omx) 설치 (선택 가능)
- PowerShell 프로필 다운로드 및 적용 (기존 프로필은 타임스탬프 백업)

> npm을 찾을 수 없으면 안내 메시지 출력 후 중단 — 재시작 후 재실행하면 됩니다.

**무인 설치 (프롬프트 없이):** 선택 메뉴를 건너뛰고 기본 구성을 그대로 설치합니다. 자동화·여러 PC 재설치에 유용합니다. 환경변수를 먼저 설정한 뒤 같은 줄을 실행하세요:

```powershell
$env:DEVSETUP_NONINTERACTIVE = 1
irm https://raw.githubusercontent.com/hd0126/dev-setup/main/install.ps1 | iex
```

> 미리 보기: `$env:DEVSETUP_DRYRUN = 1` 로 실행하면 **실제 설치 없이** "설치 계획"만 출력합니다 (점검·CI용).

---

### 🐧 Linux (Ubuntu/Debian) / 🍎 macOS

`install.sh` 한 줄로 OS를 자동 판별해 실행합니다:

```bash
curl -fsSL https://raw.githubusercontent.com/hd0126/dev-setup/main/install.sh | bash
```

**Linux (Ubuntu/Debian)** 에서 자동으로 처리합니다:
- apt로 curl, git, ripgrep, fzf, python3, python3-pip, unzip 설치; gh는 GitHub 공식 apt 저장소를 추가해 설치 (시스템 기본 버전 유지)
- NodeSource 저장소로 Node.js LTS 설치 (npm 전역 prefix를 `~/.npm-global`로 설정 → sudo 없이 `npm install -g`)
- curl로 Starship, zoxide, uv 설치
- [쾌적함 플러스 도구](#-쾌적함-플러스-도구): zsh-autosuggestions · zsh-syntax-highlighting · eza · bat · fd · git-delta · tealdeer (apt에 없는 배포판은 자동 skip)
- claude·codex는 공식 네이티브 인스톨러로, gemini-cli·omc·omx는 npm으로 설치
- `.bashrc` / `.zshrc`에 `cc`, `ccc`, `ccr`, zoxide, fzf, starship 설정 추가

**macOS** 에서 자동으로 처리합니다:
- Homebrew 없으면 자동 설치
- brew로 git, gh, ripgrep, fzf, zoxide, starship, python, uv, node 설치
- [쾌적함 플러스 도구](#-쾌적함-플러스-도구): zsh-autosuggestions · zsh-syntax-highlighting · zsh-history-substring-search · eza · bat · fd · git-delta · tealdeer
- JetBrainsMono Nerd Font 설치 (아이콘 깨짐 방지 — 터미널 앱 폰트는 직접 변경 필요)
- claude·codex는 공식 네이티브 인스톨러로, gemini-cli·omc·omx는 npm으로 설치
- `.zshrc`에 `cc`, `ccc`, `ccr`, zoxide, fzf, starship 설정 추가
- SSH는 macOS 키체인이 자동 관리 (별도 설정 불필요)

> Linux/macOS 모두 `install.sh` 한 줄로 OS를 자동 판별해 실행합니다.

> 💡 **여러 번 실행해도 안전합니다 (멱등)** — 이미 설치된 도구·이미 적용된 설정은 자동으로 건너뜁니다. 설치가 중간에 끊겼거나 뭔가 꼬였다면 같은 명령을 그냥 다시 실행하세요. 직접 꾸며둔 `.zshrc`/`.bashrc`가 있어도 같은 기능은 중복 추가되지 않고 그대로 존중됩니다.

---

## 설치 확인

새 터미널을 연 뒤 아래를 실행해 보세요. 버전이 출력되면 정상입니다:

```bash
claude --version    # Claude Code (cc 별칭으로 실행)
codex --version     # Codex CLI
starship --version  # 프롬프트
zoxide --version    # z 명령
fzf --version       # Ctrl+R 히스토리 검색
```

프롬프트나 `ll` 출력의 아이콘이 □ 로 깨져 보이면 터미널 폰트가 Nerd Font가 아닌 것입니다 → [Nerd Font 안내](#-jetbrainsmono-nerd-font) 참고.

---

## 설치 후 자동 적용되는 설정

설치 스크립트가 완료되면 각 플랫폼에 아래 설정이 자동으로 적용됩니다.

### 🪟 Windows (PowerShell)

`Microsoft.PowerShell_profile.ps1`이 `$PROFILE`에 다운로드됩니다.

| 기능 | 설명 |
|------|------|
| **PowerShell 프롬프트** | 외부 바이너리 없이 순수 PowerShell로 구현(속도 우선). `.git/HEAD`를 직접 읽어 Git 브랜치 표시, 경로 단축, 직전 명령 성공/실패에 따라 ❯ 색상 변경. (Starship은 설치되지만 이 프로필에선 미사용) |
| **zoxide** | `z <키워드>`로 방문 기록 기반 스마트 디렉토리 이동 |
| **fzf** | `Ctrl+R` 히스토리 검색, `Ctrl+T` 파일 검색 |
| **cc / ccc / ccr** | `cc`=`claude --dangerously-skip-permissions`, `ccc`=`cc --continue`, `ccr`=`cc --resume` (bypass permissions on) |
| **자동제안** | PSReadLine `PredictionSource History` — 입력 중 회색 제안, `→`로 수락 (zsh-autosuggestions 대응) |
| **SSH agent** | ssh-agent 서비스가 **이미 실행 중일 때만** `.ssh` 폴더의 키를 자동 등록(`ssh-add`). 에이전트를 직접 시작하거나 소켓을 관리하지는 않음 |
| **프로필 로드 시간** | `PowerShell loaded in {N}ms` — 터미널 시작 시 회색으로 표시 |

```powershell
# 새 도구 설치 후 캐시 갱신
Remove-Item $env:TEMP\pwsh_tools_cache.ps1
```

---

### 🐧 Linux / WSL (bash/zsh)

`.bashrc` 또는 `.zshrc` 끝에 아래 설정 블록이 추가됩니다.

| 기능 | 설명 |
|------|------|
| **Starship 프롬프트** | Git 브랜치·언어 버전 자동 표시. init 결과 캐시(`~/.cache/starship_init_*.sh`)로 로드 속도 향상 |
| **zoxide** | `z <키워드>`로 스마트 디렉토리 이동 |
| **fzf** | `Ctrl+R` 히스토리 검색, `Ctrl+T` 파일 검색 |
| **cc / ccc / ccr** | `cc`=`claude --dangerously-skip-permissions`, `ccc`=`cc --continue`, `ccr`=`cc --resume` (bypass permissions on) |
| **자동제안·색상** (zsh) | zsh-autosuggestions(회색 제안, `→`로 수락) + zsh-syntax-highlighting(유효=초록/오타=빨강) |
| **ll / la / lt** | eza 기반 ls 대체 (긴 목록·전체·트리) |
| **cat** | bat 문법 하이라이트 (Ubuntu `batcat` 자동 처리) |
| **Ctrl+T 가속** | fzf 파일검색이 fd 기반으로 동작 (.gitignore 존중, Ubuntu `fdfind` 자동 처리) |
| **git diff** | delta 하이라이트 (기존 pager 설정이 없을 때만 적용) |
| **npm 전역 경로** | `~/.npm-global/bin`을 PATH에 추가 (sudo 없이 설치한 전역 CLI 실행) |
| **셸 로드 시간** | `[shell] loaded in Xms` — 터미널 시작 시 표시 |

```bash
# Starship 캐시 초기화
rm ~/.cache/starship_init_bash.sh   # bash
rm ~/.cache/starship_init_zsh.zsh   # zsh
```

---

### 🍎 macOS (zsh)

`.zshrc` 끝에 아래 설정 블록이 추가됩니다.

| 기능 | 설명 |
|------|------|
| **Starship 프롬프트** | Git 브랜치·언어 버전 자동 표시. init 캐시(`~/.cache/starship_init_zsh.zsh`) 사용 |
| **zoxide** | `z <키워드>`로 스마트 디렉토리 이동 |
| **fzf** | `Ctrl+R` 히스토리 검색, `Ctrl+T` 파일 검색 |
| **cc / ccc / ccr** | `cc`=`claude --dangerously-skip-permissions`, `ccc`=`cc --continue`, `ccr`=`cc --resume` (bypass permissions on) |
| **자동제안·색상** | zsh-autosuggestions(회색 제안, `→`로 수락) + zsh-syntax-highlighting(유효=초록/오타=빨강) + history-substring-search(↑↓ 부분일치 검색) |
| **ll / la / lt** | eza 기반 ls 대체 (아이콘·긴 목록·전체·트리) |
| **cat** | bat 문법 하이라이트 |
| **Ctrl+T 가속** | fzf 파일검색이 fd 기반으로 동작 (.gitignore 존중) |
| **git diff** | delta 하이라이트 (기존 pager 설정이 없을 때만 적용) |
| **Homebrew (Apple Silicon)** | `/opt/homebrew/bin/brew` 존재 시 `shellenv` 자동 적용 (node·npm 전역 CLI 포함) |
| **셸 로드 시간** | `[shell] loaded in Xms` — 터미널 시작 시 표시 |
| **SSH agent** | macOS 키체인이 자동 관리 — 별도 설정 불필요 |

```bash
# Starship 캐시 초기화
rm ~/.cache/starship_init_zsh.zsh
```

---

## 이미 설치된 경우 (설정만 추가)

**가장 쉬운 방법은 [처음 설치](#처음-설치-신규)의 설치 명령을 그대로 다시 실행하는 것입니다** — 이미 설치된 도구는 건너뛰고 빠진 설정 블록만 추가되며, 직접 꾸며둔 설정과 중복되지 않습니다.

스크립트 실행 없이 수동으로 붙여넣고 싶은 경우에만 아래 블록을 사용하세요.

### 🪟 Windows (PowerShell)

PowerShell 프로필을 직접 덮어씁니다 (기존 프로필은 타임스탬프 백업됨):

```powershell
# 프로필만 다운로드
$profileUrl = "https://raw.githubusercontent.com/hd0126/dev-setup/main/Microsoft.PowerShell_profile.ps1"
if (Test-Path $PROFILE) { Copy-Item $PROFILE "$PROFILE.$(Get-Date -Format 'yyyyMMdd_HHmmss').bak" }
Invoke-WebRequest -Uri $profileUrl -OutFile $PROFILE
```

### 🐧 bash 사용자

`.bashrc` 끝에 아래 블록을 추가하세요:

```bash
cat >> ~/.bashrc << 'EOF'
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

# ── npm global bin (no-sudo prefix) ──────────────────────
export PATH="$HOME/.npm-global/bin:$PATH"

# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %dms\033[0m\n' "$(( $(date +%s%3N) - _shell_start ))"
    unset _shell_start
fi
EOF
```

### 🐧🍎 zsh 사용자 (Linux / WSL · macOS)

`.zshrc` **최상단**에 `zmodload zsh/datetime` 줄을 추가하고, 끝에 아래 블록을 추가하세요:

> `_shell_start=$EPOCHREALTIME` 은 파일 맨 위에 있어야 전체 로드 시간이 측정됩니다.

```bash
# 1) .zshrc 최상단에 타이머 시작 삽입
sed -i '1s/^/zmodload zsh\/datetime\n_shell_start=$EPOCHREALTIME\n/' ~/.zshrc

# 2) 설정 블록을 .zshrc 끝에 추가
cat >> ~/.zshrc << 'EOF'
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

# ── npm global bin (no-sudo prefix) ──────────────────────
export PATH="$HOME/.npm-global/bin:$PATH"

# ── Startup time ──────────────────────────────────────────
if [ -n "$_shell_start" ]; then
    printf '\033[0;36m[shell] loaded in %.0fms\033[0m\n' "$(( (EPOCHREALTIME - _shell_start) * 1000 ))"
    unset _shell_start
fi
EOF
```

적용 후 새 터미널을 열거나 `source ~/.bashrc` / `source ~/.zshrc` 를 실행하세요.

---

## 설치 도구 소개

### ⚡ PowerShell 7
Windows 기본 PowerShell 5.1의 최신 크로스플랫폼 후속작. 이 프로필은 pwsh 7 기준으로 동작합니다.
```powershell
pwsh --version
# PowerShell 7.x.x
```

---

### 🚀 Starship
Git 브랜치, 언어 버전, 오류 상태 등을 프롬프트에 자동 표시하는 빠른 커스텀 프롬프트.

![Starship demo](https://raw.githubusercontent.com/starship/starship/main/media/demo.gif)

설치만 됨 (winget). Windows 메인 프로필은 속도를 위해 순수 PowerShell 프롬프트를 씁니다. Starship을 이 프로필에서 쓰려면 `$PROFILE` 끝에 init 한 줄을 추가하세요:

```powershell
'Invoke-Expression (&starship init powershell)' | Add-Content $PROFILE
```

설정 커스터마이징 (프리셋: https://starship.rs/presets/):

```powershell
code ~/.config/starship.toml
```

> 참고: Windows에서 Starship은 새 터미널마다 고정비(~수백 ms)가 들어 순수 PowerShell 프롬프트보다 로드가 느립니다. 그래서 이 프로필은 기본적으로 순수 PS 프롬프트를 씁니다.

---

### 📁 zoxide
방문 기록을 학습해서 짧은 키워드만으로 디렉토리를 이동하는 스마트 cd.

![zoxide demo](https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/contrib/tutorial.webp)

```powershell
z proj            # "proj"가 포함된 가장 자주 간 폴더로 이동
z my project      # 여러 키워드 동시 매칭
z ..              # 상위 폴더로 이동
z -               # 바로 직전 폴더로 이동
zi                # fzf UI로 방문 기록에서 선택해서 이동
```

---

### 🔍 fzf
터미널에서 파일·히스토리·프로세스 등을 인터랙티브하게 검색하는 도구.
**퍼지(fuzzy) 검색** = 오타가 있어도 비슷하면 찾아줌. 예: `dcmnts` → `Documents`

![fzf preview](https://raw.githubusercontent.com/junegunn/i/master/fzf-preview.png)

```
Ctrl+R      이전에 실행한 명령어 검색 (타이핑하면 실시간 필터링)
Ctrl+T      현재 폴더 파일 검색 → 선택하면 경로가 자동 입력됨
Alt+C       폴더 목록에서 선택해서 바로 이동
```

```powershell
# 파일 선택해서 바로 열기
vim $(fzf)
code $(fzf)

# 미리보기 창 띄우기
fzf --preview 'cat {}'

# 프로세스 선택해서 종료
Get-Process | fzf | Stop-Process
```

---

### 🔤 JetBrainsMono Nerd Font
Starship 프롬프트·eza의 아이콘(Git 브랜치, 폴더 등)이 □ 로 깨지지 않으려면 Nerd Font가 필요합니다.

- **Windows**: `install.ps1`에서 선택 설치 + Windows Terminal 기본 폰트 자동 설정
- **macOS**: `setup-mac.sh`가 자동 설치. 설치 후 **터미널 앱 설정에서 폰트를 `JetBrainsMono Nerd Font`로 직접 변경**해야 적용됩니다 (Terminal.app / iTerm2 / Ghostty 공통)
- **Linux**: 수동 설치 — [nerdfonts.com](https://www.nerdfonts.com/font-downloads)에서 JetBrainsMono 다운로드 → `~/.local/share/fonts`에 압축 해제 → `fc-cache -f` 실행 → 터미널 폰트 변경

> VS Code 등 다른 앱은 설정에서 직접 `JetBrainsMono Nerd Font`로 변경해야 합니다.

---

### 🔎 ripgrep
코드에서 특정 단어·함수명을 빠르게 찾는 검색 도구. `grep`보다 수십 배 빠르고 `.gitignore`를 자동으로 적용해 불필요한 파일은 건너뜁니다.

> **fzf와 차이**: fzf는 파일 이름·히스토리 목록에서 고르는 UI 도구, ripgrep은 파일 **안의 내용**을 검색하는 도구. 코딩을 하지 않는다면 생략해도 됩니다.

![ripgrep demo](https://burntsushi.net/stuff/ripgrep1.png)

```powershell
rg "function"           # 현재 디렉토리 전체에서 검색
rg "TODO" src/          # 특정 폴더만 검색
rg -i "error"           # 대소문자 무시
rg -w "main"            # 단어 단위로 정확히 매칭 ("mainly" 제외)
rg -t py "import"       # Python 파일만 검색
rg -t js "console.log"  # JS 파일만 검색
rg -n "def "            # 줄 번호 표시
rg -C 3 "catch"         # 검색 결과 앞뒤 3줄씩 같이 표시
rg -l "TODO"            # 파일 이름만 출력 (내용 말고)
```

---

### ✨ 쾌적함 플러스 도구

전부 셸 시작속도 영향이 거의 0인 가벼운 도구들입니다. **설치돼 있을 때만 활성화**되므로 일부가 없어도(구버전 Ubuntu 등) 에러 없이 그냥 건너뜁니다.

| 도구 | 하는 일 | 써보기 |
|------|---------|--------|
| **zsh-autosuggestions** | 히스토리 기반 회색 자동제안 | 타이핑 중 `→` 키로 수락 |
| **zsh-syntax-highlighting** | 명령이 유효하면 초록, 오타면 빨강 | 입력만 하면 자동 |
| **zsh-history-substring-search** | 입력한 단어가 **포함된** 히스토리를 ↑↓로 탐색 (macOS) | `git` 입력 후 `↑` |
| **eza** | `ls` 대체 — 아이콘·git 상태 표시 | `ll`, `la`, `lt`(트리) |
| **bat** | `cat` 대체 — 문법 하이라이트·줄번호 | `cat 파일.py` |
| **fd** | `find` 대체 — fzf `Ctrl+T`의 파일 소스로 자동 연동 | `fd 검색어` |
| **git-delta** | `git diff`를 문법 하이라이트로 (pager 자동 설정) | `git diff` |
| **tealdeer** | `man` 대신 실전 예시 위주 도움말 | `tldr tar` |

> Ubuntu에서는 패키지 사정상 `bat`→`batcat`, `fd`→`fdfind` 명령명이지만 alias가 자동으로 처리합니다. Windows는 PSReadLine 내장 예측이 zsh-autosuggestions 역할을 대신합니다.

---

### 🤖 Claude Code
Anthropic의 AI 코딩 CLI. 터미널에서 자연어로 코드 작성·수정·디버깅·리뷰. 네이티브 인스톨러로 설치되며 백그라운드 자동 업데이트(Anthropic 권장).

네이티브 인스톨러로 설치 (설치 스크립트가 자동 실행 — 수동 설치 시):

```powershell
irm https://claude.ai/install.ps1 | iex
```

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

`cc`는 `claude --dangerously-skip-permissions`의 alias로, 권한 확인 없이 파일 읽기·쓰기·명령 실행을 자동 승인합니다 (bypass permissions on).

```bash
cc                     # claude --dangerously-skip-permissions (bypass permissions on)
ccc                    # 이전 대화 이어서 (--continue)
ccr                    # 중단된 세션 복구 (--resume)

# 사용 예시
cc '이 함수 테스트 작성해줘'
cc '버그 찾아서 고쳐줘'
cc '이 코드 리뷰해줘'
```

> `--dangerously-skip-permissions` 없이 실행하려면 `claude` 명령을 직접 사용하세요.

---

### 🟩 Node.js LTS
JavaScript 런타임. gemini-cli · omx 등 npm CLI 설치에 필요 (codex · Claude Code는 네이티브라 불필요).

```powershell
node --version
npm install -g <패키지>
```

---

### 🐍 Python 3.12
범용 프로그래밍 언어. 데이터 분석·자동화·AI 개발에 널리 사용.

```powershell
python --version
pip install <패키지>
```

---

### ⚡ uv
빠른 Python 패키지·venv 관리자 (Rust 단일 바이너리). pip·venv를 대체하며 수십 배 빠릅니다.

```powershell
uv venv                # 가상환경 생성
uv pip install <패키지>  # 패키지 설치
uv run <스크립트>        # 환경 자동 구성 후 실행
```

---

### 🐙 Git
버전 관리 도구. GitHub CLI · Claude Code 사용에 필요.

```powershell
git clone <repo>
git commit -m "feat: 기능 추가"
git push
```

---

### 🐱 GitHub CLI
터미널에서 GitHub PR · 이슈 · Gist 관리.

```powershell
gh pr create           # PR 생성
gh issue list          # 이슈 목록
gh gist list           # Gist 목록
```

---

### 🔵 Codex CLI
OpenAI의 AI 코딩 CLI. 터미널에서 자연어로 코드 작성·수정·실행. Node 불필요, 자동 업데이트(OpenAI 권장). 첫 실행 시 `codex auth` 로그인 필요.

네이티브 인스톨러로 설치 (install.ps1이 자동 실행 — 수동 설치 시):

```powershell
irm https://chatgpt.com/codex/install.ps1 | iex
```

> ⚠️ 설치 중 `tar: Cannot connect to C:` 오류가 나면, PATH 앞쪽에 **Git의 유닉스 `tar`(`...\Git\usr\bin`)** 가 끼어 Windows 경로를 원격 호스트로 오해한 것입니다. `where.exe tar` 로 확인하고, `C:\Windows\System32\tar.exe` 가 먼저 잡히는 일반 PowerShell 창에서 위 명령을 다시 실행하세요.

```bash
codex                         # 대화형 모드 실행
codex 'tests 작성해줘'        # 한 줄 명령으로 실행
codex auth                    # OpenAI 계정 로그인
```

---

### 💎 Gemini CLI (`@google/gemini-cli`)
Google Gemini AI 어시스턴트. 첫 실행 시 브라우저 OAuth 자동 실행 (Google 계정 로그인).

```bash
gemini                        # 대화형 모드 실행
gemini '이 코드 설명해줘'     # 한 줄 명령으로 실행
gemini '리팩토링 해줘'
```

---

### 🔗 oh-my-codex (`omx`)
[GitHub](https://github.com/Yeachan-Heo/oh-my-codex) · [문서](https://yeachan-heo.github.io/oh-my-codex-website/)

Codex CLI용 워크플로우 레이어. Codex를 실행 엔진으로 유지하면서 명확화→계획→실행의 일관된 워크플로우를 제공. 프로젝트 상태는 `.omx/`에 저장.

```bash
omx --madmax --high           # OMX 기본 실행 (권장)
omx setup                     # 초기 설정
omx doctor                    # 설치 상태 확인

# Codex 세션 내 주요 스킬
$deep-interview "요구사항 명확히 해줘"   # 심층 인터뷰로 요구사항 정리
$ralplan "계획 수립하고 트레이드오프 검토" # 계획 수립 및 승인
$ralph "승인된 계획 완료까지 실행"        # 반복 실행 루프
$team 3:executor "병렬로 실행해줘"       # 병렬 멀티에이전트 실행
```

---

### 🧩 oh-my-claude-sisyphus (`omc`)
[GitHub](https://github.com/Yeachan-Heo/oh-my-claudecode) · [문서](https://yeachan-heo.github.io/oh-my-claudecode-website)

Claude Code용 멀티에이전트 오케스트레이션 레이어. planner·executor·reviewer 등 전문 에이전트를 자동 라우팅하고 HUD로 실시간 토큰·세션 상태 표시. _"Don't learn Claude Code. Just use OMC."_

```bash
omc setup                     # 초기 설정 (HUD·훅 자동 구성)

# Claude Code 세션 내 주요 스킬
/autopilot "REST API 만들어줘"  # 자율 실행 모드 (계획→구현→검증)
/ralph "승인된 계획 완료까지"    # 반복 완료 루프
/ccg "이 PR 리뷰해줘"           # Codex + Gemini 병렬 자문
/team                           # 멀티에이전트 팀 오케스트레이션
```

---

## Claude Code 플러그인 (로그인 후 수동 실행)

```powershell
# 1. 로그인
claude login

# 2. oh-my-claudecode (omc)
claude plugin marketplace add Yeachan-Heo/oh-my-claudecode
claude plugin install oh-my-claudecode@omc

# 3. codex 플러그인
claude plugin marketplace add openai/codex-plugin-cc
claude plugin install codex@openai-codex

# 4. honeypot 마켓플레이스
claude plugin marketplace add https://github.com/orientpine/honeypot.git

# 5. Karpathy 가이드라인 플러그인
claude plugin marketplace add forrestchang/andrej-karpathy-skills
claude plugin install andrej-karpathy-skills@karpathy-skills
```

---

## 단축키 / 명령어

| 명령어 | 설명 |
|--------|------|
| `cc` | `claude --dangerously-skip-permissions` (bypass permissions on) |
| `ccc` | `cc --continue` (이전 대화 이어서) |
| `ccr` | `cc --resume` (세션 복구) |
| `which <명령어>` | 명령어 설치 경로 확인 |
| `touch <파일>` | 빈 파일 생성 (있으면 수정 시간 갱신) |
| `z <키워드>` | 자주 간 디렉토리로 바로 이동 |
| `zi` | fzf UI로 디렉토리 선택 후 이동 |
| `Ctrl+R` | fzf로 히스토리 퍼지 검색 |
| `Ctrl+T` | fzf로 파일 검색 후 경로 삽입 (fd 설치 시 .gitignore 존중) |
| `↑ / ↓` | 히스토리 검색 (입력한 내용 기준) |
| `→` | 회색 자동제안 수락 (zsh-autosuggestions / PSReadLine) |
| `ll` / `la` / `lt` | eza 긴 목록 / 숨김 포함 / 트리 |
| `cat <파일>` | bat 문법 하이라이트로 표시 |
| `tldr <명령>` | 실전 예시 위주 명령어 도움말 |
| `conda` | Conda 초기화 (첫 호출 시 로드) |

---

## 프로필 캐시 관리

### 🪟 Windows (PowerShell)

프로필은 첫 실행 시 도구(zoxide·fzf·starship) 유무를 한 번만 검사해 캐시에 저장합니다.
이후 실행에서는 캐시만 읽으므로 `Get-Command` 탐색 비용 없이 빠릅니다.

```powershell
# 새 도구를 설치한 후 캐시 갱신 (필수)
Remove-Item $env:TEMP\pwsh_tools_cache.ps1

# zoxide init 캐시 재생성
Remove-Item $env:TEMP\zoxide_init_cache.ps1
```

### 🐧 Linux / 🍎 macOS

Starship init 결과만 캐시에 저장합니다. 새 터미널을 열 때 자동으로 갱신되지만 수동으로 초기화하려면:

```bash
# Starship init 캐시 삭제 (다음 셸 시작 시 자동 재생성)
rm ~/.cache/starship_init_bash.sh   # bash
rm ~/.cache/starship_init_zsh.zsh   # zsh
```

---

## 파일 수정 후 업데이트

repo를 클론한 폴더에서 파일 수정 후:

```bash
git add -A && git commit -m "update" && git push
```
