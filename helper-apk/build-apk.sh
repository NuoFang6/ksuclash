#!/usr/bin/env bash
# build-apk.sh - 构建 MihomoControl.apk（aapt2 + javac + d8 + zipalign + apksigner）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="$ROOT/helper-apk"
TOOLS="$ROOT/tools"
BT="$TOOLS/bt"

# java
if ! command -v java >/dev/null 2>&1; then
    export PATH="/c/9919/jdk/graalvm-jdk-25/bin:$PATH"
fi

OSNAME="$(uname -s)"
case "$OSNAME" in
    MINGW*|MSYS*|CYGWIN*) EXE=.exe; BAT=.bat ;;
    *) EXE=""; BAT="" ;;
esac

AAPT2="$BT/aapt2$EXE"
D8="$BT/d8$BAT"
APKSIGNER="$BT/apksigner$BAT"
ZIPALIGN="$BT/zipalign$EXE"
PLATFORM="$TOOLS/android.jar"

VC="${VC:-10000}"
VN="${VN:-1.0.0}"

BUILD="$APK/build"
rm -rf "$BUILD"
mkdir -p "$BUILD/gen" "$BUILD/obj" "$BUILD/dex"

echo ">> aapt2 compile"
"$AAPT2" compile --dir "$APK/res" -o "$BUILD/res.zip"

echo ">> aapt2 link"
"$AAPT2" link -o "$BUILD/base.apk" -I "$PLATFORM" \
    --manifest "$APK/AndroidManifest.xml" \
    --java "$BUILD/gen" \
    --min-sdk-version 26 --target-sdk-version 34 \
    --version-code "$VC" --version-name "$VN" \
    --auto-add-overlay "$BUILD/res.zip"

echo ">> javac"
# MSYS/Git Bash 下需把 jar 路径转成 Windows 形式再传给原生 javac/d8
PLAT_CP="$PLATFORM"
command -v cygpath >/dev/null 2>&1 && PLAT_CP="$(cygpath -m "$PLATFORM")"

# 切到 helper-apk 目录用相对路径运行（Windows 原生工具不识别 /c/... 路径）
(
    cd "$APK"
    find java build/gen -name '*.java' > build/sources.txt
    javac --release 11 -encoding UTF-8 -classpath "$PLAT_CP" -d build/obj @build/sources.txt

    echo ">> d8"
    find build/obj -name '*.class' > build/classes.txt
    "$D8" --release --lib "$PLAT_CP" --min-api 26 --output build/dex @build/classes.txt
)

echo ">> package"
cp "$BUILD/base.apk" "$BUILD/app.apk"
(cd "$BUILD/dex" && jar -uf "$BUILD/app.apk" classes.dex)

echo ">> zipalign"
"$ZIPALIGN" -f 4 "$BUILD/app.apk" "$BUILD/aligned.apk"

echo ">> apksigner"
# 签名密钥优先用仓库内置（CI 与本地产物签名一致，升级可覆盖安装）
KS="$APK/ksuclash.keystore"
[ -f "$KS" ] || KS="$TOOLS/ksuclash.keystore"
"$APKSIGNER" sign --ks "$KS" --ks-key-alias ksuclash \
    --ks-pass pass:ksuclash123 --key-pass pass:ksuclash123 \
    --out "$ROOT/module/bin/MihomoControl.apk" "$BUILD/aligned.apk"
"$APKSIGNER" verify --print-certs "$ROOT/module/bin/MihomoControl.apk" | head -3

echo ">> done: module/bin/MihomoControl.apk"
