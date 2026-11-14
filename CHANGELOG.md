# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고,
버전은 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

## [Unreleased]

아직 릴리스되지 않은 변경 사항이 여기 쌓입니다. 착수 전 아이디어는
[BACKLOG.md](BACKLOG.md)에 있습니다.

### Changed
- **Gemini CLI → Antigravity CLI(`agy`)로 교체 (3-OS 공통)** — Google이 2026-06-18부터
  무료·AI Pro·Ultra 계정의 Gemini CLI 요청을 받지 않아(유료 API 키·기업 라이선스만 유지),
  기본 설치되던 `@google/gemini-cli`가 초보 사용자에겐 설치돼도 못 쓰는 도구가 됐다.
  Google 공식 네이티브 인스톨러(`antigravity.google/cli/install.{sh,ps1}`)로 `agy`를
  설치한다 — Node 불필요, 자체 업데이트.
- **예전 스크립트로 깔린 Gemini CLI는 물어보고 삭제 (3-OS 공통)** — 새 스크립트는 Gemini
  CLI를 더 이상 업데이트하지 않아, 남겨 두면 개인 계정으론 로그인도 안 되는 버전에 멈춘다.
  npm 전역 패키지가 있으면 `y/N`(기본 N)으로 묻고, 무인 설치·dry-run·tty 없는 환경에서는
  묻지 않고 안내만 출력한다. npm 패키지만 지우고 `~/.gemini`는 절대 건드리지 않는다 —
  Antigravity CLI가 `GEMINI.md`·MCP 설정·스킬을 그 폴더에서 계속 쓰고,
  `agy plugin import gemini`도 예전 확장을 거기서 읽는다. 삭제 실패는 설치 실패로 세지 않는다.
- **Python 버전 고정 제거 → uv가 최신 Python 설치 (3-OS 공통)** — Windows `Python.Python.3.12`
  (winget)와 macOS `python@3.12`(brew) 고정이 3.15 출시 뒤에도 남아 있었다. 이제
  `uv python install --default`로 최신 안정판을 `~/.local/bin`에 설치한다(구버전 uv 등
  `--default` 실패 시 버전 명령만 만드는 기본 설치로 폴백). macOS의 Homebrew Python
  libexec PATH 블록은 더 이상 추가하지 않는다(기존 `.zshrc`의 블록은 그대로 존중).
  - **기존 Python 환경은 존중한다.** Windows는 PATH에 이미 진짜 Python이 있으면(Store판
    포함 — 빈 스텁과는 `--version` 실행 결과로 구별) 건너뛴다. Linux/macOS는 `python3`가
    `/usr/bin` 밖에서 잡히거나 `pip --user` 패키지가 있으면 `--default` 없이 버전 명령만
    설치해 기본 `python3`를 그대로 둔다.
  - **동작 변화(새 PC)**: 기존 환경이 없으면 새 터미널의 `python`/`python3`가 uv 관리
    Python을 가리킨다(Linux/macOS의 시스템 `/usr/bin/python3`는 그대로 남는다). Windows는
    `~\.local\bin`을 사용자 PATH에서 `...\Microsoft\WindowsApps`(스토어를 여는 `python.exe`
    스텁)보다 앞에 둔다.
- **Linux에서 `python3-pip` 설치 제거** — 최근 Ubuntu/Debian은 시스템 `pip install`을
  PEP 668로 막아 초보가 첫 명령부터 에러를 본다. 패키지 설치는 uv로 통일(README 안내 갱신).
- **macOS·Linux의 omc(oh-my-claudecode)를 npm 대신 Claude Code 플러그인으로** — 공식
  README는 모든 OS에서 플러그인 설치를 권장하고 npm(`oh-my-claude-sisyphus`)은 대안으로만
  소개한다. 이제 macOS·Linux도 Windows처럼 npm 설치를 하지 않고, 설치 끝에 로그인 후 실행할
  플러그인 명령을 안내한다(macOS·Linux는 이 안내 자체가 없었다). 예전에 npm으로 깔린 것은
  지우지 않고, 더 이상 업데이트하지 않는다는 안내만 출력한다.
- **Windows 메뉴에서 Starship 기본 해제** — Windows 프로필은 순수 PowerShell 프롬프트를 써서
  Starship을 쓰지 않는데도 기본 설치했다. 켜면 Enter마다 외부 exe를 실행해, 실시간 백신
  검사가 있는 PC에서 프롬프트 1회 1.6~2.0초가 걸렸다(순수 PS 프롬프트 17~103ms). 메뉴의
  선택지로는 남긴다. macOS·Linux는 실제로 쓰므로 그대로. 이미 설치된 Starship은 지우지 않는다.
- **Nerd Font·Node.js 메뉴 설명 정정** — Nerd Font는 Starship용만이 아니다: 예전 콘솔
  창의 기본 폰트 Consolas에는 프롬프트 화살표 `❯`(U+276F)가 없어 □로 깨진다(Cascadia
  Mono에는 있음). Node.js는 Claude Code 본체엔 필요 없지만 omc 플러그인의 훅 25개와
  MCP 서버가 `node`로 실행된다. 이 PR 초안의 "Node는 omx에만 필요" 설명을 바로잡고,
  Windows에서 Node를 해제했는데 PC에도 없으면 경고를 출력한다(강제로 다시 켜지는 않음).
- **Windows에 eza·bat·fd·delta·tldr 추가 (macOS·Linux와 같은 구성)** — winget 공식 ID
  (`eza-community.eza`, `sharkdp.bat`, `sharkdp.fd`, `dandavison.delta`, `dbrgn.tealdeer`)로
  설치하고, 실패해도 전체 실패로 세지 않는 선택 항목으로 둔다. 프로필에 `ll`·`la`·`lt`(eza),
  fd 기반 fzf `Ctrl+T`(직접 설정한 `FZF_DEFAULT_COMMAND`가 있으면 유지)를 추가한다. git pager는
  어느 수준(시스템·전역·로컬 설정, `GIT_PAGER`·`PAGER`)에도 설정이 없을 때만 delta로 바꾸고,
  tldr 페이지가 비어 있으면 받는다(실패하면 다음 실행 때 다시 시도). PowerShell의 `cat`(Get-Content)은 객체 파이프라인 동작이 달라
  bat으로 덮어쓰지 않는다.
- **winget 설치 여부를 한 번에 조회** — 패키지마다 `winget list --id`를 부르던 것을
  `winget export` 한 번(JSON)으로 바꿨다. 실시간 백신 검사가 있는 PC에서 패키지당 약 14초,
  10개에 139초 걸리던 조회가 1회 약 57초로 줄었다. JSON이라 UI 언어·열 잘림의 영향도 없다.
  실패하면 기존 패키지별 조회로 돌아간다.
- **프로필 캐시를 파일 하나로 합치고 자동 갱신** — 도구 유무 캐시와 zoxide init 캐시 두
  파일을 `pwsh_profile_cache.ps1` 하나로 합쳤다. 첫 줄에 프로필·도구 exe의 수정 시각을 적어
  두고 매번 비교해, 프로필을 고치거나 `winget upgrade zoxide` 등으로 exe가 바뀌면 자동으로
  다시 만든다(예전에는 캐시를 지우기 전까지 옛 init을 계속 썼다). 수정 시각은 심볼릭 링크가
  가리키는 실제 파일에서 읽고, 캐시는 임시 파일에 쓴 뒤 교체해 터미널 여러 개가 동시에 열려도
  반쯤 쓰인 파일을 읽지 않는다. 시작 시간은 이전과 비슷하다
  (측정상 둘 다 약 2.5~4초이며 대부분 PSReadLine 로드 시간).
- **Windows 네이티브 설치 분기 정리** — 네이티브 도구가 셋으로 늘면서, codex 전용인
  symlink 우회·standalone 정리 재시도를 "Claude Code가 아니면"이 아니라 codex 여부로
  판별하도록 변경(다른 도구 설치 실패 시 Codex 설치 폴더를 지우지 않도록).

### Fixed
- **네이티브 claude·codex가 이미 있으면 npm 사본이 영영 남던 문제** — npm 사본 제거가
  네이티브를 새로 설치할 때만 실행돼, 네이티브가 이미 있는 PC에서는 "already installed"로
  건너뛰며 npm 사본이 계속 남았다. Claude Code용 `~\.local\bin`은 사용자 PATH 끝에 붙으므로
  (uv가 Python을 새로 설치할 때만 앞으로 옮김), Node를 먼저 설치한 PC에서는 `%APPDATA%\npm`이
  앞에 와서 새 터미널에서도 옛 npm판이 실행될 수 있다. 이제 두 경로 모두에서 `npm ls`로 사본을
  찾아 제거한다(같은 도구라 묻지 않음). 단, **네이티브 설치가 끝난 뒤에만**, 그리고 네이티브
  폴더가 사용자·시스템 PATH에 있을 때만 지운다 — 그렇지 않으면 새 터미널에서 명령이 아예
  사라질 수 있다. 네이티브가 이미 있는 Claude Code는 먼저 `~\.local\bin`을 PATH에 넣는다.
- **Linux에서 zsh-history-substring-search가 한 번도 동작하지 않던 문제** — Ubuntu·Debian
  어느 버전에도 이 apt 패키지가 없어(packages.ubuntu.com·packages.debian.org 검색 결과 없음)
  설치가 "저장소에 없음"으로 조용히 건너뛰어졌고, `.zshrc` 블록은 존재하지 않는 `/usr/share`
  경로만 봤다. 공식 저장소를 `~/.zsh`로 `git clone`하고(임시 폴더에 받은 뒤 옮겨 반쯤 받은
  폴더가 남지 않게 함), 블록이 `~/.zsh` 경로를 먼저 보도록 바꿨다. 예전 버전이 넣은 블록은
  그 한 줄만 제자리에서 고친다(멱등).
- **Windows 설치 중 PowerShell 프로필이 통째로 한 번 로드되던 문제** — 실행 정책을
  `RemoteSigned`로 바꾸는 자식 `pwsh`가 `-NoProfile` 없이 실행돼, 설정 한 줄 바꾸는 데
  사용자 프로필(zoxide·PSReadLine 등)을 전부 로드했다. 실제 설치에서 약 8초가 걸렸고
  설치 출력 중간에 `PowerShell loaded in 7777ms`가 찍혔다. `-NoProfile`을 추가.
- **사용자 PATH에 폴더를 추가할 때 `%VAR%` 항목이 고정값으로 굳던 문제** — Claude Code
  설치·zoxide 폴백에서 폴더를 PATH에 넣을 때 `[Environment]::GetEnvironmentVariable`로 읽은
  (이미 확장된) 값을 다시 써서, `%JAVA_HOME%\bin`이나 Windows 기본 항목
  `%USERPROFILE%\AppData\Local\Microsoft\WindowsApps` 같은 항목이 그 시점의 값으로 굳고
  값 종류도 REG_EXPAND_SZ에서 REG_SZ로 바뀌었다. 레지스트리 원문과 값 종류를 보존하는
  `Add-UserPath`로 교체.
- **Windows one-liner 첫 줄 에러(`'﻿#' 용어는 ... 인식되지 않습니다`)** — `install.ps1`의
  UTF-8 BOM이 `irm | iex`에서 첫 `#`에 붙어 명령으로 해석됐다(PS 5.1·7 공통, 모든
  사용자). 파일 안에서 우회할 방법이 없어 BOM을 제거. PS 5.1에서 `-File`로 직접 실행하면
  한글 메시지가 깨져 보일 수 있다(파싱·동작은 정상, 검증함).
- **한글/공백 계정명에서 임시 파일 삭제 실패** — `$env:TEMP`가 8.3 짧은 경로
  (`C:\Users\곽대운~1\...`)이면 `Remove-Item`이 존재하는 파일을 지우지 못하고
  `-ErrorAction`도 무시한 채 에러를 냈다. 그 결과 도구 캐시가 무효화되지 않아 새로 설치한
  zoxide/fzf가 새 터미널에서도 비활성으로 남았다. 긴 경로로 변환 후 삭제하는
  `Remove-TempPath`로 TEMP 삭제 5곳을 교체.
- **README·프로필의 수동 캐시 삭제 안내도 같은 이유로 실패** — `Remove-Item $env:TEMP\...`를
  `Remove-Item ([IO.Path]::GetFullPath("$env:TEMP\..."))`로 바꾸고 이유를 README에 설명.

## [0.3.0] - 2026-07-15

### Security
- **`curl | bash`에서 현재 폴더의 스크립트를 오인 실행하던 문제 수정** — `install.sh`가
  파이프 실행 시 `$0`("bash") 폴백으로 `SCRIPT_DIR`를 현재 디렉터리로 잡아, 거기에
  `setup-*.sh`가 있으면 GitHub 대신 로컬 파일을 실행했다(악성 레포 안에서 실행 시 임의
  코드 실행 위험). `BASH_SOURCE`가 실제 파일일 때만 로컬 경로를 쓰도록 수정 — 레포 클론
  안에서 파일로 실행하면 여전히 로컬 파일을 사용한다(기존 의도 유지).
- **issue-triage 워크플로의 `claude-code-action`을 전체 커밋 SHA로 고정** — 쓰기 토큰을
  쓰는 제3자 Action의 이동 가능한 `@v1` 태그는 공급망 위험(GitHub 보안 권장사항 반영).
  권한 분리 등 나머지 강화 항목은 BACKLOG의 schedule 재개 전 필수 조건으로 기록.

### Fixed
- **패키지 설치가 실패해도 종료 코드가 0이던 문제** — 3-OS 스크립트 모두 실패 목록만
  출력하고 정상 종료해 CI·프로비저닝이 실패를 감지하지 못했다. 실패 항목이 있으면
  `exit 1`로 종료(Windows는 `irm | iex`에서 `exit`가 터미널 세션을 닫으므로 파일 실행일
  때만 종료 코드 전달).
- **macOS "Node.js LTS"가 실제로는 Current를 설치하던 문제** — `brew install node`는
  Current 라인이다. nodejs.org 릴리스 인덱스에서 최신 LTS 메이저를 동적으로 판별해
  `node@<major>`를 설치·링크하도록 수정(Linux NodeSource `setup_lts.x`와 파리티, 특정
  버전 하드코딩 없음). 판별 실패 시 기존 동작(brew node)으로 폴백하고, 기존 설치가
  LTS가 아니면 경고만 남기고 존중한다.
- **macOS에서 Homebrew python@3.12의 `python3`/`pip3`가 PATH에 없던 문제** — 무버전
  명령은 `libexec/bin`에만 생성되므로 해당 경로를 .zshrc PATH에 추가(Apple Silicon·
  Intel 양쪽 prefix 하드코딩, 멱등).
- **PowerShell 프롬프트가 git worktree/submodule에서 브랜치를 못 읽던 문제** — `.git`이
  디렉터리가 아닌 `gitdir: <경로>` 파일인 경우를 따라가 HEAD를 읽도록 수정.

## [0.2.0] - 2026-07-03

### Added
- **터미널 이슈 리포터 개선** — 설치 실패 시 `gh` 로그인 여부를 먼저 확인하고,
  미로그인이면 `gh auth login --web` 브라우저 로그인을 즉석 안내한 뒤 이슈를 제출한다
  (기존: 실패 후 "gh auth login 하고 재시도" 안내 → 선제 안내로 개선). Mac·Linux·Windows 3-OS 공통.
- **설치 성공 시 GitHub star 제안** — 전부 성공했을 때만 `y/N`로 star를 묻고, 로그인 상태면
  `gh api -X PUT user/starred/...`로 터미널에서 즉시 star. 이미 star했으면 다시 묻지 않고,
  비대화형(tty 없음) 환경에선 조용히 스킵. Mac·Linux·Windows 3-OS 공통.
- **Claude 이슈 자동 검토 워크플로** (`.github/workflows/claude-issue-triage.yml`) — 등록된
  이슈를 `anthropics/claude-code-action`으로 분석해 진단 코멘트 또는 수정 PR을 남긴다.
  미처리 이슈가 없으면 Claude를 기동하지 않아 비용을 아끼고, 수정은 항상 새 브랜치 + PR로만
  하며(main 직접 push 금지), 이슈 본문은 비신뢰 입력으로 취급(프롬프트 인젝션 방어)한다.
  현재 API 크레딧 미확보로 `schedule` 트리거는 보류, `workflow_dispatch`(수동)만 활성.
- **Linux에 `zsh-history-substring-search` 추가** — apt 설치 + `↑↓` 부분일치 검색 설정 블록을
  추가해 macOS와 기능을 맞춘다(플러그인 로드 순서상 syntax-highlighting 뒤에 배치).

### Fixed
- **다운로드 실패가 "설치 성공"으로 오보고되던 문제** — `set -e`만 있고 `pipefail`이 없어
  `curl | sh` 파이프에서 curl 실패가 `sh`의 exit 0에 가려졌다. Linux의 Starship·zoxide·uv·
  GitHub CLI 키링·NodeSource 설치를 국소 pipefail 서브셸로 감싸 실제 실패를 정확히 보고하도록
  수정. GitHub CLI 키링은 실패 시 손상된 keyring을 정리해 이후 `apt-get update` 파손을 방지한다.
  전역 pipefail은 npm 버전 감지 파이프(`grep` 미매치=exit 1)를 죽이므로 의도적으로 쓰지 않았다.
- **macOS Homebrew 설치 오보고** — `bash -c "$(curl ...)"`는 명령 치환이라 pipefail 대상이
  아니고 `ok "Homebrew"`가 무조건 실행됐다. 다운로드 후 실행 + 설치 후 `command -v brew`
  재검증으로 실제 실패를 감지하도록 수정(Intel `/usr/local/bin/brew` 경로도 추가).
- **Windows Terminal 폰트 자동 설정이 PowerShell 5.1에서 실패하던 문제** — 기본
  `settings.json`의 `//` 주석에서 `ConvertFrom-Json`이 예외를 던졌다(PS7은 관대, 5.1은 실패).
  파싱 전에 줄 시작 주석만 제거하도록 수정.

### Changed
- **매일 자동 검토(`schedule`) 트리거 보류** — Anthropic 구독 한도와 console API 크레딧이 별개
  지갑이라, API 크레딧 없이는 워크플로가 매번 실패한다. `schedule` 트리거를 주석 처리하고
  수동 실행만 유지(크레딧 충전 또는 구독 Agent SDK 크레딧 정책 재개 시 주석 두 줄만 풀면 재개).
- **README** — Linux의 history-substring 지원 반영, 이슈 자동 검토 안내 문구를 실제 상태에
  맞게 정정.

## [0.1.0] - 2026-06-19

초기 릴리스 — Windows·macOS·Linux 3-OS 부트스트랩(`install.ps1` / `install.sh` +
`setup-mac.sh` / `setup-linux.sh`), AI 코딩 CLI(Claude Code·codex·gemini-cli·omx·omc)와
모던 터미널 도구 설치, 셸 프로필 설정, 초보자용 이슈 폼과 lint 워크플로.

이 CHANGELOG 도입 이전이라 항목별 기록은 없습니다. 상세 변경은 `8b53290`(2026-06-19)부터의
커밋 로그를 참조하십시오.
