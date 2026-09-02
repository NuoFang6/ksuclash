set -e

echo "GOOS=$GOOS, GOARCH=$GOARCH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build"
mkdir -p "$OUTPUT_DIR"


# 构建参数
VERSION="${VN:-1.0.0}"
COMMIT=$(git -C "$ROOT/mihomo" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# LDFLAGS：体积优化 + 版本注入
LDFLAGS="
    -s -w
    -extldflags --static
    -X github.com/metacubex/mihomo/constant.Version=$VERSION
    -X github.com/metacubex/mihomo/constant.BuildTime=$BUILD_TIME
    -X github.com/metacubex/mihomo/constant.GitCommit=$COMMIT
"

echo "🔨 编译 mihomo..."
cd "$ROOT/mihomo"

# 悬浮面板脚本供 hub/route 的 go:embed 使用（mihomo-patches/0005）。
# panel.js 不入补丁，始终以本仓库最新版为准。
cp "$ROOT/module/webroot-src/panel.js" hub/route/panel.js

CGO_ENABLED=0 go build \
    -tags "with_gvisor" \
    -trimpath \
    -buildvcs=false \
    -ldflags="$LDFLAGS" \
    -o "$OUTPUT_DIR/mihomo" .

echo "✅ 编译完成: $OUTPUT_DIR/mihomo"
ls -lh "$OUTPUT_DIR/mihomo"