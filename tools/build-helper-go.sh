#!/usr/bin/env bash
# 编译 helper-go（suclash_helper 单二进制）
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT/build"
mkdir -p "$OUTPUT_DIR"

echo "🔨 开始编译 helper-go ($GOOS/$GOARCH)"
cd "$ROOT/helper-go"

CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w" \
    -o "$OUTPUT_DIR/suclash_helper" .
