#!/usr/bin/env bash
# get-tools.sh - 下载 APK 构建工具（build-tools 34 + platforms;android-34），生成签名密钥
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
mkdir -p "$TOOLS"
cd "$TOOLS"

OSNAME="$(uname -s)"
case "$OSNAME" in
    MINGW*|MSYS*|CYGWIN*) BT_ZIP=build-tools_r34-windows.zip; WIN=1; TAR=/c/Windows/System32/tar.exe ;;
    Linux*)               BT_ZIP=build-tools_r34-linux.zip;   WIN=0; TAR=tar ;;
    *) echo "unsupported OS: $OSNAME"; exit 1 ;;
esac

if ! command -v java >/dev/null 2>&1; then
    export PATH="/c/9919/jdk/graalvm-jdk-25/bin:$PATH"
fi

if [ ! -d "$TOOLS/bt" ]; then
    echo ">> downloading $BT_ZIP"
    curl -sSL -o bt.zip "https://dl.google.com/android/repository/$BT_ZIP"
    if [ "$WIN" = 1 ]; then "$TAR" -xf bt.zip; else unzip -qo bt.zip; fi
    BTDIR="$(find . -maxdepth 1 -type d -name 'android-*' | head -1)"
    mv "$BTDIR" bt
    rm -f bt.zip
fi

if [ ! -f "$TOOLS/android.jar" ]; then
    echo ">> fetching android.jar via sdkmanager (platforms;android-34)"
    if [ "$WIN" = 1 ]; then CTL_ZIP=commandlinetools-win-13114758_latest.zip; SDKM=sdk/cmdline-tools/latest/bin/sdkmanager.bat
    else CTL_ZIP=commandlinetools-linux-13114758_latest.zip; SDKM=sdk/cmdline-tools/latest/bin/sdkmanager; fi
    curl -sSL -o ctl.zip "https://dl.google.com/android/repository/$CTL_ZIP"
    # GNU tar 不能解 zip（Windows 自带 bsdtar 可以），Linux 用 unzip
    if [ "$WIN" = 1 ]; then "$TAR" -xf ctl.zip; else unzip -qo ctl.zip; fi
    mkdir -p sdk/cmdline-tools
    mv cmdline-tools "$TOOLS/sdk/cmdline-tools/latest"
    rm -f ctl.zip
    # pipefail 下 yes 的 SIGPIPE(141) 会让整条管道失败：先单独接受许可，再静默安装
    yes | "$TOOLS/$SDKM" --sdk_root="$TOOLS/sdk" --licenses > /dev/null 2>&1 || true
    "$TOOLS/$SDKM" --sdk_root="$TOOLS/sdk" "platforms;android-34" > /dev/null 2>&1
    cp "$TOOLS/sdk/platforms/android-34/android.jar" "$TOOLS/android.jar"
    rm -rf "$TOOLS/sdk"
fi

# 签名密钥已随仓库提供（helper-apk/suclash.keystore），与 CI 签名一致。
# 仅当两者都缺失（如 fork 后未提交密钥）才本地生成，保证脚本能独立跑通。
if [ ! -f "$ROOT/helper-apk/suclash.keystore" ] && [ ! -f "$TOOLS/suclash.keystore" ]; then
    echo ">> generating signing keystore"
    keytool -genkeypair -keystore "$TOOLS/suclash.keystore" -alias suclash \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass suclash123 -keypass suclash123 \
        -dname "CN=SU Clash, O=suclash, C=CN"
fi

echo ">> tools ready:"
ls -1 "$TOOLS"
