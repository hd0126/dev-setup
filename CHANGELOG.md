# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따릅니다.

## [2026-07-15]

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

## [2026-07-03]

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
