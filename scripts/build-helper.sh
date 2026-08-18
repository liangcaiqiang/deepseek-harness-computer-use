#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER_PATH="${DSH_COMPUTER_USE_HELPER:-$HOME/.dsh/pcctl/pcctl_gui}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "未找到 swiftc。请在 macOS 上安装 Xcode Command Line Tools。" >&2
  exit 1
fi

mkdir -p "$(dirname "$HELPER_PATH")"
swiftc "$ROOT_DIR/helper/pcctl_gui.swift" -o "$HELPER_PATH"
chmod 755 "$HELPER_PATH"
echo "Helper 已构建：$HELPER_PATH"
