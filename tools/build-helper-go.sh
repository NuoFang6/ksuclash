set -e

cd helper-go

echo "🔨 开始编译 helper-go..."
echo "GOOS=$GOOS, GOARCH=$GOARCH"

CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w -extldflags '-static'" \
    -o "${GITHUB_WORKSPACE}/build/suclash_helper" ./main.go