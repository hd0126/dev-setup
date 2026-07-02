#!/usr/bin/env bash
# 셸 설정 섹션의 멱등성·시나리오 테스트
# CI(ubuntu/macos)와 로컬에서 실행: bash tests/test_shell_config.sh
# macOS에서는 /bin/bash(3.2)로 섹션을 실행해 구버전 bash 호환까지 함께 검증한다.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# macOS 기본 /bin/bash(3.2)를 우선 사용 — 스크립트의 실사용 인터프리터
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN=bash

hash_of() {
    if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d' ' -f1
    else md5 -q "$1"; fi
}
zsh_check() {
    if command -v zsh >/dev/null 2>&1; then zsh -n "$1"; else return 0; fi
}

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# ── 섹션 추출 ─────────────────────────────────────────────
sed -n '/^# ── 6\. Shell config/,/^# ── 7\. SSH agent/p' "$REPO/setup-mac.sh" | sed '$d' > "$T/mac.sh"
sed -n '/^# Re-run safe, per-feature/,/^done$/p' "$REPO/setup-linux.sh" > "$T/linux.sh"
[ -s "$T/mac.sh" ]   || { echo "mac 섹션 추출 실패"; exit 1; }
[ -s "$T/linux.sh" ] || { echo "linux 섹션 추출 실패"; exit 1; }

run_mac() { # $1=fake home
    HOME="$1" "$BASH_BIN" -c 'set -e; ok(){ :; }; warn(){ :; }; fail(){ :; }; info(){ :; }; source "'"$T"'/mac.sh"'
}
run_linux() { # $1=fake home
    HOME="$1" "$BASH_BIN" -c 'set -e; ok(){ :; }; warn(){ :; }; fail(){ :; }; info(){ :; }; SHELL_CONFIGS=("$HOME/.bashrc" "$HOME/.zshrc"); source "'"$T"'/linux.sh"'
}

echo "== [mac] A. 빈 .zshrc: 생성 + 재실행 멱등 =="
H="$T/macA"; mkdir -p "$H"
run_mac "$H"
zsh_check "$H/.zshrc" && pass "생성물 zsh 문법" || fail "생성물 zsh 문법"
M1=$(hash_of "$H/.zshrc"); run_mac "$H"
if [ "$M1" = "$(hash_of "$H/.zshrc")" ]; then pass "재실행 무변경(멱등)"; else fail "재실행 시 변경됨"; fi
if [ "$(grep -c 'alias cc=' "$H/.zshrc")" = 1 ]; then pass "alias cc 중복 없음"; else fail "alias cc 중복"; fi

echo "== [mac] B. 부분 구성(alias만): 누락 추가·중복 없음·타이머 미추가 =="
H="$T/macB"; mkdir -p "$H"; printf 'alias cc="claude --dangerously-skip-permissions"\n' > "$H/.zshrc"
run_mac "$H"
if [ "$(grep -c 'alias cc=' "$H/.zshrc")" = 1 ]; then pass "alias cc 중복 없음"; else fail "alias cc 중복"; fi
if grep -q 'zoxide init' "$H/.zshrc"; then pass "누락 기능(zoxide) 추가"; else fail "zoxide 미추가"; fi
if grep -q '_shell_start' "$H/.zshrc"; then fail "수동구성인데 타이머 추가됨"; else pass "타이머 미추가"; fi

echo "== [mac] C. alias cc='clang' 존중: claude alias 미추가 =="
H="$T/macC"; mkdir -p "$H"; printf "alias cc='clang'\n" > "$H/.zshrc"
run_mac "$H"
if grep -q 'claude --dangerously' "$H/.zshrc"; then fail "개인 cc alias를 덮어씀"; else pass "개인 cc alias 존중"; fi

echo "== [mac] D. 부분 재실행: 새 블록이 syntax-highlighting 앞에 삽입 =="
H="$T/macD"; mkdir -p "$H"; run_mac "$H"
# fd 블록 제거 후 재실행 → syntax 블록보다 앞에 삽입돼야 함
python3 - "$H/.zshrc" <<'PY' 2>/dev/null || perl -0pi -e 's/\n# ── fd \+ fzf 연동.*?\nfi\n/\n/s' "$H/.zshrc"
import sys, re
p = sys.argv[1]; t = open(p).read()
t = re.sub(r'\n# ── fd \+ fzf 연동.*?\nfi\n', '\n', t, flags=re.S)
open(p, 'w').write(t)
PY
run_mac "$H"
fd_line=$(grep -n '── fd + fzf' "$H/.zshrc" | cut -d: -f1 | head -1)
sh_line=$(grep -n '── zsh-syntax-highlighting' "$H/.zshrc" | cut -d: -f1 | head -1)
if [ -n "$fd_line" ] && [ -n "$sh_line" ] && [ "$fd_line" -lt "$sh_line" ]; then pass "syntax-highlighting 앞 삽입"; else fail "삽입 순서 (fd=$fd_line, syntax=$sh_line)"; fi
zsh_check "$H/.zshrc" && pass "삽입 후 zsh 문법" || fail "삽입 후 zsh 문법"

echo "== [linux] E. 빈 rc 2종: 생성·멱등·문법 =="
H="$T/linE"; mkdir -p "$H"; touch "$H/.bashrc" "$H/.zshrc"
run_linux "$H"
B1=$(hash_of "$H/.bashrc"); Z1=$(hash_of "$H/.zshrc"); run_linux "$H"
if [ "$B1" = "$(hash_of "$H/.bashrc")" ] && [ "$Z1" = "$(hash_of "$H/.zshrc")" ]; then pass "재실행 무변경(멱등)"; else fail "재실행 시 변경됨"; fi
"$BASH_BIN" -n "$H/.bashrc" && pass "bashrc 문법" || fail "bashrc 문법"
zsh_check "$H/.zshrc" && pass "zshrc 문법" || fail "zshrc 문법"

echo "== [linux] F. zoxide가 ~/.local/bin에만 있어도 새 셸에서 z 정의 =="
H="$T/linF"; mkdir -p "$H/.local/bin"; touch "$H/.bashrc" "$H/.zshrc"
printf '#!/bin/sh\nif [ "$1" = "init" ]; then echo "z() { echo zoxide-works; }"; fi\n' > "$H/.local/bin/zoxide"
chmod +x "$H/.local/bin/zoxide"
run_linux "$H"
out=$(HOME="$H" PATH="/usr/bin:/bin" "$BASH_BIN" -c 'source "$HOME/.bashrc" 2>/dev/null; type z >/dev/null 2>&1 && z || echo MISSING')
if [ "$out" = "zoxide-works" ]; then pass "z 정의됨 (PATH 순서 수정 확인)"; else fail "z 미정의: $out"; fi

echo "== [linux] G. 배포판 스톡 alias ll이 있어도 eza 블록 추가 =="
H="$T/linG"; mkdir -p "$H"; printf "alias ll='ls -alF'\nalias la='ls -A'\n" > "$H/.bashrc"; touch "$H/.zshrc"
run_linux "$H"
if grep -q 'eza -l' "$H/.bashrc"; then pass "eza 블록 추가(스톡 alias 오탐 해소)"; else fail "eza 블록 미추가"; fi

echo ""
echo "== 결과: ${PASSED} passed / ${FAILED} failed =="
[ "$FAILED" -eq 0 ]
