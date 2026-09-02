#!/usr/bin/env bash
# build-helper-apk.sh - 构建 MihomoControl.apk（aapt2 + kotlinc + R8/d8 + zipalign + apksigner）
# 构建工具统一在 build/ 下（由 get-tools.sh 下载），输出到 module/bin/MihomoControl.apk。
# 源码为 Kotlin（helper-apk/src）；aapt2 生成的 R.java 由 kotlinc 解析符号、javac 编译字节码。
# 用法: bash tools/get-tools.sh && bash tools/build-helper-apk.sh
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
APKSIGNER="$TOOLS/bt/apksigner$BAT"
ZIPALIGN="$TOOLS/bt/zipalign$EXE"
D8_JAR="$TOOLS/bt/lib/d8.jar"
# kotlinc.bat 在 JDK 24+ 的 kotlin-runner 路径下 stdlib 解析异常，改用 preloader 直启编译器
KOTLIN_PRELOADER="$TOOLS/kotlinc/lib/kotlin-preloader.jar"
KOTLIN_COMPILER_JAR="$TOOLS/kotlinc/lib/kotlin-compiler.jar"
KOTLIN_STDLIB="$TOOLS/kotlinc/lib/kotlin-stdlib.jar"
COR_CORE="$TOOLS/kx/coroutines-core.jar"
COR_ANDROID="$TOOLS/kx/coroutines-android.jar"
PLATFORM="$TOOLS/android.jar"

for f in "$AAPT2" "$PLATFORM" "$KOTLIN_PRELOADER" "$KOTLIN_COMPILER_JAR" "$KOTLIN_STDLIB" "$COR_CORE" "$COR_ANDROID" "$D8_JAR"; do
    [ -f "$f" ] || { echo "! 缺少构建工具: $f（先运行 bash tools/get-tools.sh）" >&2; exit 1; }
done

# MSYS/Git Bash 下需把路径转成 Windows 形式再传给原生 javac/kotlinc/R8
w() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || echo "$1"; }
PLAT_CP="$(w "$PLATFORM")"
COR_CORE_W="$(w "$COR_CORE")"
COR_ANDROID_W="$(w "$COR_ANDROID")"
D8_JAR_W="$(w "$D8_JAR")"
KT_PRELOADER_W="$(w "$KOTLIN_PRELOADER")"
KT_COMPILER_W="$(w "$KOTLIN_COMPILER_JAR")"

# JDK 24+ 抑制 sun.misc.Unsafe 弃用告警
JAVA_OPTS=""
JAVA_V="$(java -version 2>&1 | head -1)"
[[ "$JAVA_V" =~ \"([0-9]+) ]] && { [ "${BASH_REMATCH[1]}" -ge 24 ] && JAVA_OPTS="--sun-misc-unsafe-memory-access=allow --enable-native-access=ALL-UNNAMED"; } || true

# 统一的 Kotlin 编译器调用：preloader 直启 K2JVMCompiler
kotlinc() {
    java $JAVA_OPTS -cp "$KT_PRELOADER_W" org.jetbrains.kotlin.preloading.Preloader \
        -cp "$KT_COMPILER_W" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler "$@"
}

VC="${VC:-10000}"
VN="${VN:-1.0.0}"

BUILD="$APK/build"
rm -rf "$BUILD" 2>/dev/null || true
[ -d "$BUILD" ] && { echo "! build 目录无法删除，请手动清理: $BUILD"; exit 1; }
mkdir -p "$BUILD/gen" "$BUILD/obj" "$BUILD/kclasses" "$BUILD/dex"
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

    echo ">> kotlinc"
    # R.java 一并作为源码传入：kotlinc 只解析符号（R 引用），不编译 Java
    KT_SRC="$(find src -name '*.kt')"
    R_SRC="$(find build/gen -name '*.java' | while read -r f; do w "$f"; done)"
    kotlinc -jvm-target 11 -nowarn \
        -classpath "$PLAT_CP;$COR_CORE_W;$COR_ANDROID_W" \
        -d build/kclasses $KT_SRC $R_SRC

    echo ">> javac (R.java)"
    find build/gen -name '*.java' > build/sources.txt
    javac --release 11 -encoding UTF-8 -classpath "$PLAT_CP" -d build/obj @build/sources.txt

    # 打包 Kotlin 字节码为 jar，供 R8/d8 输入
    jar -cf build/kclasses.jar -C build/kclasses .

    echo ">> R8 (裁剪 kotlin-stdlib，失败则回退 d8)"
    cat > build/r8.pro <<'EOF'
# Manifest 组件与 WebView JS 桥需反射可达：整个应用包保留，R8 只裁剪 kotlin-stdlib/coroutines
-keep class io.github.suclash.control.** { *; }
-dontwarn kotlinx.coroutines.**
-dontwarn java.lang.invoke.**
-dontwarn org.jetbrains.annotations.**
EOF
    if java -cp "$D8_JAR_W" com.android.tools.r8.R8 \
        --release --min-api 26 --lib "$PLAT_CP" \
        --pg-conf build/r8.pro --pg-map-output build/map.txt \
        --output build/dex \
        build/kclasses.jar "$(w "$KOTLIN_STDLIB")" "$COR_CORE_W" "$COR_ANDROID_W" \
        $(find build/obj -name '*.class') 2>build/r8.log; then
        echo ">> R8 完成 ($(wc -l < build/r8.log) 条警告)"
    else
        echo "!! R8 失败，回退 d8（APK 会偏大）:"
        tail -5 build/r8.log || true
        java -cp "$D8_JAR_W" com.android.tools.r8.D8 \
            --release --min-api 26 --lib "$PLAT_CP" \
            --output build/dex \
            build/kclasses.jar "$(w "$KOTLIN_STDLIB")" "$COR_CORE_W" "$COR_ANDROID_W" \
            $(find build/obj -name '*.class')
    fi

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
