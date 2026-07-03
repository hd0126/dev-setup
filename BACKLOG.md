# Backlog

착수 전 아이디어·미완 작업을 휘발되지 않게 모아두는 곳입니다.
확정되어 버전에 편입되면 [CHANGELOG.md](CHANGELOG.md)로 옮깁니다.
우선순위: **High** = 다음에 볼 것 · **Med** = 여유 될 때 · **Low** = 있으면 좋음.

## 열린 항목

- [ ] **[High] API 크레딧 확보 후 자동 triage 재개** — `console.anthropic.com`에서 API 크레딧
  충전(또는 구독 Agent SDK 크레딧 정책 재개) 후, `.github/workflows/claude-issue-triage.yml`의
  `schedule:` 주석 두 줄을 풀고 엔드투엔드 재검증(수동 실행 → Claude가 실제로 코멘트/PR 생성).
  현재는 배관 검증 완료·크레딧만 부족한 보류 상태.

- [ ] **[Med] README에 `curl | bash` 신뢰 모델 명시** — 부트스트랩 특성상 원격 스크립트를
  체크섬/서명 핀 없이 실행한다는 점을 "accepted risk"로 문서화(리뷰 지적). 내가 통제하는
  도구 버전 핀 고정도 함께 검토.

- [ ] **[Low] `~/.local/bin` PATH 멱등성 체크 Mac/Linux 통일** — Mac은 3개 rc 파일을 grep,
  Linux는 처리 중인 단일 cfg만 grep. 동작엔 문제없으나 시그니처를 블록 주석 마커 등 더
  구체적인 값으로 바꿔 견고화(현재는 bare `.local/bin` 문자열이라 zoxide 블록과 겹칠 여지).

- [ ] **[Low] install.ps1 Windows Terminal `settings.json` 트레일링 콤마 대응** — WinPS 5.1의
  `//` 주석 파싱 실패는 수정했으나, 트레일링 콤마가 있는 파일은 여전히 `catch`로 빠져
  수동 안내만 나간다. 콤마 정리 후 파싱하거나 5.1 전용 안내 분기 검토.

## 완료 (참고용, CHANGELOG로 이관됨)

- [x] 다운로드 실패 오보고(pipefail) 수정 — 2026-07-03
- [x] Linux `zsh-history-substring-search` 추가 — 2026-07-03
- [x] WinPS 5.1 폰트 자동설정 `//` 주석 파싱 수정 — 2026-07-03
- [x] 이슈 리포터 gh 로그인 선제 안내 + star 프롬프트(3-OS 파리티) — 2026-07-03
- [x] Claude 이슈 자동 검토 워크플로 구축 — 2026-07-03
