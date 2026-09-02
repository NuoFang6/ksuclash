#!/usr/bin/env bash
# get-tools.sh - 下载 helper-apk 构建所需的全部工具到 build/：
#   build/bt/{aapt2,zipalign,d8.bat,apksigner.bat,lib/d8.jar}  ← Android build-tools r34
#   build/android.jar                                          ← platform-34
#   build/kotlinc/                                             ← Kotlin 编译器 2.x
#   build/kx/coroutines-core.jar / coroutines-android.jar      ← kotlinx-coroutines
# 用法: bash tools/get-tools.sh && bash tools/build-helper-apk.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/build"
mkdir -p "$TOOLS/bt/lib" "$TOOLS/kx" "$TOOLS/dl"

# ---- JDK（仅用于下载校验，构建脚本自行定位 java）----
if ! command -v java >/dev/null 2>&1; then
    export PATH="/c/9919/jdk/graalvm-jdk-25/bin:$PATH"
fi

OSNAME="$(uname -s)"
case "$OSNAME" in
    MINGW*|MSYS*|CYGWIN*) BT_ZIP="build-tools_r34-windows.zip"; BT_DIR_GLOB="android-14" ;;
    *)                    BT_ZIP="build-tools_r34-linux.zip";   BT_DIR_GLOB="android-14" ;;
esac

# MSYS 下 curl 对嵌套目录的绝对路径 (/c/...) 写入不可靠，统一先 cd 再用相对路径
cd "$TOOLS"

fetch() { # fetch <url> <out>
    local url="$1" out="$2"
    [ -s "$out" ] && { echo ">> 已存在: $out"; return 0; }
    echo ">> 下载: $url"
    curl -fL --retry 3 -o "$out" "$url"
}

# ---- 1. build-tools（aapt2 / zipalign / d8 / apksigner）----
if [ ! -f "bt/aapt2.exe" ] && [ ! -f "bt/aapt2" ]; then
    fetch "https://dl.google.com/android/repository/$BT_ZIP" "dl/bt.zip"
    rm -rf "dl/bt-extract"
    mkdir -p "dl/bt-extract"
    unzip -q "dl/bt.zip" -d "dl/bt-extract"
    SRC_BT="$(find dl/bt-extract -maxdepth 2 -type d -name "$BT_DIR_GLOB" | head -1)"
    [ -n "$SRC_BT" ] || SRC_BT="$(find dl/bt-extract -maxdepth 2 -type d | tail -1)"
    cp "$SRC_BT"/aapt2* bt/ 2>/dev/null || true
    cp "$SRC_BT"/zipalign* bt/ 2>/dev/null || true
    cp "$SRC_BT"/d8* bt/ 2>/dev/null || true
    cp "$SRC_BT"/apksigner* bt/ 2>/dev/null || true
    cp -r "$SRC_BT"/lib bt/
    chmod +x bt/* 2>/dev/null || true
    echo ">> build-tools 就绪: $TOOLS/bt"
else
    echo ">> 已存在 build-tools"
fi

# ---- 2. platform android.jar ----
if [ ! -f "android.jar" ]; then
    OK=""
    for pf in platform-34_r02.zip platform-34_r01.zip platform-34-ext7_r03.zip platform-34-ext7_r02.zip; do
        if fetch "https://dl.google.com/android/repository/$pf" "dl/platform-34.zip"; then
            rm -rf "dl/pf-extract"
            mkdir -p "dl/pf-extract"
            unzip -q "dl/platform-34.zip" -d "dl/pf-extract"
            AJ="$(find dl/pf-extract -name android.jar | head -1)"
            [ -n "$AJ" ] || continue
            cp "$AJ" "android.jar"
            OK="$pf"; break
        fi
    done
    [ -n "$OK" ] || { echo "! 全部 platform-34 下载失败" >&2; exit 1; }
    echo ">> android.jar 就绪 ($OK)"
else
    echo ">> 已存在 android.jar"
fi

# ---- 3. Kotlin 编译器（按候选版本依次尝试）----
if [ ! -x "kotlinc/bin/kotlinc" ] && [ ! -f "kotlinc/bin/kotlinc.bat" ]; then
    OK=""
    for v in 2.2.20 2.2.10 2.2.0 2.1.21 2.1.20; do
        if fetch "https://github.com/JetBrains/kotlin/releases/download/v$v/kotlin-compiler-$v.zip" "dl/kotlinc-$v.zip"; then
            rm -rf kotlinc
            unzip -q "dl/kotlinc-$v.zip" -d .
            OK="$v"; break
        fi
    done
    [ -n "$OK" ] || { echo "! 全部 Kotlin 编译器版本下载失败" >&2; exit 1; }
    echo ">> kotlinc $OK 就绪"
else
    echo ">> 已存在 kotlinc"
fi

# ---- 4. kotlinx-coroutines（core + android 主线程调度器）----
COR_VER="1.10.2"
MVN="https://repo1.maven.org/maven2/org/jetbrains/kotlinx"
fetch "$MVN/kotlinx-coroutines-core-jvm/$COR_VER/kotlinx-coroutines-core-jvm-$COR_VER.jar" "kx/coroutines-core.jar"
fetch "$MVN/kotlinx-coroutines-android/$COR_VER/kotlinx-coroutines-android-$COR_VER.jar" "kx/coroutines-android.jar"

# ---- 5. 清理下载缓存（保留工具本体）----
rm -rf dl

echo ">> 全部工具就绪: $TOOLS"
