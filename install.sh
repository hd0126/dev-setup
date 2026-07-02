#!/usr/bin/env bash
# Universal installer — auto-detects OS and runs the appropriate setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/hd0126/dev-setup/main/install.sh | bash

set -e

REPO_RAW="https://raw.githubusercontent.com/hd0126/dev-setup/main"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║      Dev Environment Installer       ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── OS 판별 ──────────────────────────────────────────────
OS=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
else
    echo -e "${RED}[ERROR]${NC} Unsupported OS: $OSTYPE"
    echo ""
    echo "Windows 사용자는 PowerShell에서 아래 명령어를 실행하세요:"
    echo "  irm $REPO_RAW/install.ps1 | iex"
    exit 1
fi

echo -e "${GREEN}[OS]${NC} Detected: $OS"
echo ""

# ── 설치 스크립트 실행 ────────────────────────────────────
# 레포 클론 안에서 실행하면(스크립트 옆에 setup-*.sh 존재) 로컬 파일을 사용한다
# — 항상 GitHub main을 받으면 로컬에서 수정한 내용이 조용히 무시되기 때문.
# `curl | bash` 실행은 스크립트 파일 경로가 없으므로 자동으로 다운로드 경로를 탄다.
SETUP_SCRIPT="setup-${OS}.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$SETUP_SCRIPT" ]; then
    echo -e "${CYAN}[..]${NC} Running local $SETUP_SCRIPT (repo clone detected: $SCRIPT_DIR)..."
    echo ""
    bash "$SCRIPT_DIR/$SETUP_SCRIPT"
else
    TMP_SCRIPT=$(mktemp)
    echo -e "${CYAN}[..]${NC} Downloading $SETUP_SCRIPT..."
    curl -fsSL "$REPO_RAW/$SETUP_SCRIPT" -o "$TMP_SCRIPT"
    chmod +x "$TMP_SCRIPT"
    echo -e "${CYAN}[..]${NC} Running $SETUP_SCRIPT..."
    echo ""
    bash "$TMP_SCRIPT"
    rm -f "$TMP_SCRIPT"
fi
