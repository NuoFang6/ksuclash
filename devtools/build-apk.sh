#!/usr/bin/env bash
# build-apk.sh - 构建 MihomoControl.apk（aapt2 + javac + d8 + zipalign + apksigner）
# 构建工具统一在 build/ 下（由 get-tools.sh 下载），输出到 module/bin/MihomoControl.apk。
# 原生工具（aapt2/zipalign 等）统一在 helper-apk 目录内用相对路径调用，
# 避免 MSYS 绝对路径（/c/...）不被原生 exe 识别的问题。
# 用法: bash devtools/get-tools.sh && bash devtools/build-apk.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="$ROOT/helper-apk"
TOOLS="$ROOT/build"

# java
if ! command -v java >/dev/null 2>&1; then
    export PATH="/c/9919/jdk/graalvm-jdk-25/bin:$PATH"
fi

OSNAME="$(uname -s)"
case "$OSNAME" in
    MINGW*|MSYS*|CYGWIN*) EXE=.exe; BAT=.bat ;;
    *) EXE=""; BAT="" ;;
esac

AAPT2="$TOOLS/bt/aapt2$EXE"
D8="$TOOLS/bt/d8$BAT"
APKSIGNER="$TOOLS/bt/apksigner$BAT"
ZIPALIGN="$TOOLS/bt/zipalign$EXE"
PLATFORM="$TOOLS/android.jar"

if [ ! -f "$AAPT2" ] || [ ! -f "$PLATFORM" ]; then
    echo "! build tools not found under $TOOLS. Run: bash devtools/get-tools.sh first" >&2
    exit 1
fi

# MSYS/Git Bash 下需把 jar 路径转成 Windows 形式再传给原生 javac/d8
PLAT_CP="$PLATFORM"
command -v cygpath >/dev/null 2>&1 && PLAT_CP="$(cygpath -m "$PLATFORM")"

VC="${VC:-10000}"
VN="${VN:-1.0.0}"

BUILD="$APK/build"
rm -rf "$BUILD" 2>/dev/null || true
[ -d "$BUILD" ] && { echo "! build 目录无法删除，请手动清理: $BUILD"; exit 1; }
mkdir -p "$BUILD/gen" "$BUILD/obj" "$BUILD/dex"
mkdir -p "$ROOT/module/bin"   # APK 输出目录（CI 全新 checkout 时可能不存在）

(
    cd "$APK"

    echo ">> aapt2 compile"
    "$AAPT2" compile --dir res -o build/res.zip

    echo ">> aapt2 link"
    "$AAPT2" link -o build/base.apk -I "$PLAT_CP" \
        --manifest AndroidManifest.xml \
        --java build/gen \
        --min-sdk-version 26 --target-sdk-version 34 \
        --version-code "$VC" --version-name "$VN" \
        --auto-add-overlay build/res.zip

    echo ">> javac"
    find java build/gen -name '*.java' > build/sources.txt
    javac --release 11 -encoding UTF-8 -classpath "$PLAT_CP" -d build/obj @build/sources.txt

    echo ">> d8"
    find build/obj -name '*.class' > build/classes.txt
    "$D8" --release --lib "$PLAT_CP" --min-api 26 --output build/dex @build/classes.txt

    echo ">> package"
    cp build/base.apk build/app.apk
    (cd build/dex && jar -uf ../app.apk classes.dex)

    echo ">> zipalign"
    "$ZIPALIGN" -f 4 build/app.apk build/aligned.apk

    echo ">> apksigner"
    # 签名密钥优先用仓库内置（CI 与本地产物签名一致，升级可覆盖安装）
    KS="$APK/suclash.keystore"
    [ -f "$KS" ] || KS="$TOOLS/suclash.keystore"
    KS_OUT="$ROOT/module/bin/MihomoControl.apk"
    # apksigner 是 Java 程序，参数路径需为 Windows 形式
    KS_W="$KS"; KS_OUT_W="$KS_OUT"
    command -v cygpath >/dev/null 2>&1 && {
        KS_W="$(cygpath -m "$KS")"; KS_OUT_W="$(cygpath -m "$KS_OUT")"
    }
    "$APKSIGNER" sign --ks "$KS_W" --ks-key-alias suclash \
        --ks-pass pass:suclash123 --key-pass pass:suclash123 \
        --out "$KS_OUT_W" build/aligned.apk
    "$APKSIGNER" verify --print-certs "$KS_OUT_W" | head -3
)

echo ">> done: module/bin/MihomoControl.apk"
