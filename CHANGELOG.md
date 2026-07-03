# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따릅니다.

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
