#!/usr/bin/env bash
# =====================================================================
# 警告：不要在开发电脑上随意运行此脚本！
# 此脚本用于 CI/CD 环境及本地开发环境的自动化依赖配置。
# 它会自动下载并安装构建 helper-apk 所需的工具链。
# =====================================================================

# 遇到任何未处理的错误立即退出
set -e 

# ==============================
# 0. 架构检查 (仅限 amd64)
# ==============================
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "❌ 此脚本仅支持在 amd64 (x86_64) 架构上运行。当前检测到的架构: $ARCH"
    exit 1
fi

# ==============================
# 辅助函数：环境检测与变量注入
# ==============================
is_ci() {
    [ -n "$GITHUB_ACTIONS" ] || [ -n "$CI" ]
}

add_to_env() {
    local key=$1 value=$2
    export "$key=$value"
    # 仅在 CI 环境写入 GITHUB_ENV
    if is_ci && [ -n "$GITHUB_ENV" ]; then
        echo "$key=$value" >> "$GITHUB_ENV"
    fi
    # 无论何时都写入本地 .env 文件
    echo "export $key=\"$value\"" >> "$ENV_FILE"
}

add_to_path() {
    local dir=$1
    export PATH="$dir:$PATH"
    # 仅在 CI 环境写入 GITHUB_PATH
    if is_ci && [ -n "$GITHUB_PATH" ]; then
        echo "$dir" >> "$GITHUB_PATH"
    fi
    # 无论何时都写入本地 .env 文件
    echo "export PATH=\"$dir:\$PATH\"" >> "$ENV_FILE"
}

# ==============================
# 1. 基础依赖检查与自动安装
# ==============================
REQUIRED_CMDS=(curl tar unzip jq awk grep sort find)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "⚠️ 缺少必要工具: $cmd"
        if is_ci; then
            echo "❌ CI 环境缺少基础工具，请检查 Runner 镜像配置。"
            exit 1
        else
            echo "🔧 本地环境缺少 $cmd，尝试使用 apt 自动安装 (需要 sudo 权限)..."
            sudo apt update && sudo apt install -y "$cmd" || { echo "❌ 自动安装失败，请手动执行: sudo apt install $cmd"; exit 1; }
        fi
    fi
done

# ==============================
# 2. 目录初始化与缓存文件准备
# ==============================
TOOLS_DIR="${GITHUB_WORKSPACE:-$(pwd)}/tmp"
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

# 生成本地环境专用的 .env 文件
ENV_FILE="$TOOLS_DIR/.env"
echo "# =========================================" > "$ENV_FILE"
echo "# 自动生成的环境变量文件" >> "$ENV_FILE"
echo "# 本地调试请在终端执行: source $ENV_FILE" >> "$ENV_FILE"
echo "# =========================================" >> "$ENV_FILE"

# ==============================
# 3. 安装 Azul Zulu JDK
# ==============================
java_version="25"
echo "📦 [1/5] 正在处理 Azul Zulu JDK $java_version..."

# 缓存检测：如果目录已存在则跳过下载
JDK_DIR=$(ls -d zulu${java_version}* 2>/dev/null | head -n 1)
if [ -z "$JDK_DIR" ] || [ ! -d "$JDK_DIR" ]; then
    echo "⬇️ 未检测到缓存，正在下载 JDK..."
    JDK_URL=$(curl -s -X GET "https://api.azul.com/metadata/v1/zulu/packages/?java_version=${java_version}&os=linux-glibc&arch=x64&archive_type=tar.gz&java_package_type=jdk&javafx_bundled=false&crac_supported=false&crs_supported=false&support_term=lts&latest=true&release_status=ga&availability_types=ca&certifications=tck&page=1&page_size=100" -H "accept: application/json" | jq -r '.[0].download_url')
    
    if [ -z "$JDK_URL" ] || [ "$JDK_URL" == "null" ]; then
        echo "❌ 无法从 Azul API 获取 JDK 下载链接"
        exit 1
    fi
    
    curl -fSL "$JDK_URL" -o zulu.tar.gz
    tar -xzf zulu.tar.gz
    rm zulu.tar.gz
    JDK_DIR=$(ls -d zulu${java_version}* 2>/dev/null | head -n 1)
else
    echo "✅ 发现已缓存的 JDK 目录: $JDK_DIR"
fi

JDK_PATH="$TOOLS_DIR/$JDK_DIR"
add_to_env "JAVA_HOME" "$JDK_PATH"
add_to_path "$JDK_PATH/bin"

java -version
echo "✅ JDK $java_version 配置完毕"

# ==============================
# 4. 安装 Android CLI 及 Build Tools
# ==============================
echo "📦 [2/5] 正在处理 Android CLI 和 Build Tools..."

# 检查 android 命令是否可用，不可用则安装
if ! command -v android &>/dev/null; then
    echo "⬇️ 未检测到 android 命令，正在安装 Android CLI..."
    curl -fsSL https://dl.google.com/android/cli/latest/linux_x86_64/install.sh | bash
    
    # 尝试将常见安装路径加入 PATH
    for p in "$HOME/.android/cli/bin" "$HOME/.local/bin" "/usr/local/bin"; do
        if [ -f "$p/android" ]; then
            add_to_path "$p"
            break
        fi
    done
fi

# 再次确认 android 命令可用
if ! command -v android &>/dev/null; then
    echo "❌ 安装后仍未找到 android 命令，请检查安装日志。"
    exit 1
fi

# 获取并安装最新的 build-tools
BUILD_TOOLS_VER=$(android sdk list "build-tools*" --all 2>/dev/null | grep -Eo "build-tools;[0-9.]+" | sort -V | tail -n 1)
if [ -z "$BUILD_TOOLS_VER" ]; then
    echo "⚠️ 无法获取最新版本号，使用默认版本 build-tools;35.0.0"
    BUILD_TOOLS_VER="build-tools;35.0.0"
fi

echo "正在安装 $BUILD_TOOLS_VER..."
android sdk install "$BUILD_TOOLS_VER" >/dev/null 2>&1 || true

# 动态查找 aapt2 来确定 build-tools 的绝对路径 (兼容不同 SDK 安装位置)
BUILD_TOOLS_BIN=$(find "$HOME" -path "*/build-tools/*/aapt2" -type f 2>/dev/null | sort -V | tail -n 1)
if [ -n "$BUILD_TOOLS_BIN" ]; then
    BUILD_TOOLS_LATEST=$(dirname "$BUILD_TOOLS_BIN")
    add_to_path "$BUILD_TOOLS_LATEST"
    echo "✅ Build Tools 配置完毕: $BUILD_TOOLS_LATEST"
else
    echo "❌ 未找到 aapt2，build-tools 可能安装失败。"
    exit 1
fi

# ==============================
# 5. 安装 Platform (android.jar)
# ==============================
echo "📦 [3/5] 正在处理 Android Platform..."

LATEST_STABLE=$(android sdk list "platforms*" --all 2>/dev/null | grep -Eo "platforms;android-[0-9.]+" | grep -v "ext" | sort -V | tail -n 1)
if [ -z "$LATEST_STABLE" ]; then
    LATEST_STABLE="platforms;android-35"
fi

echo "正在安装 $LATEST_STABLE..."
android sdk install "$LATEST_STABLE" >/dev/null 2>&1 || true

# 动态查找 android.jar
PLATFORM_ANDROID_JAR=$(find "$HOME" -path "*/$LATEST_STABLE/android.jar" -type f 2>/dev/null | head -n 1)
if [ -z "$PLATFORM_ANDROID_JAR" ]; then
    # 降级查找：如果精确版本没找到，找任意最新的 android.jar
    PLATFORM_ANDROID_JAR=$(find "$HOME" -path "*/platforms/*/android.jar" -type f 2>/dev/null | sort -V | tail -n 1)
fi

add_to_env "platform_android_jar" "$PLATFORM_ANDROID_JAR"
echo "✅ Platform 配置完毕: $LATEST_STABLE"

# ==============================
# 6. 安装 Kotlin 编译器
# ==============================
echo "📦 [4/5] 正在处理 Kotlin 编译器..."

if [ ! -d "kotlinc" ]; then
    echo "⬇️ 未检测到缓存，正在通过 GitHub API 获取最新 Kotlin 编译器..."
    # 脱离对 gh (GitHub CLI) 的依赖，使用纯 curl 解析 API
    KOTLIN_URL=$(curl -s https://api.github.com/repos/JetBrains/kotlin/releases/latest | grep -o 'https://github.com/JetBrains/kotlin/releases/download/[^"]*kotlin-compiler-[^"]*\.zip' | head -n 1)
    
    if [ -z "$KOTLIN_URL" ]; then
        echo "❌ 无法从 GitHub API 获取 Kotlin 编译器下载链接"
        exit 1
    fi
    
    curl -fSL "$KOTLIN_URL" -o kotlin.zip
    unzip -q kotlin.zip
    rm kotlin.zip
else
    echo "✅ 发现已缓存的 kotlinc 目录"
fi

KOTLIN_BIN_PATH="$TOOLS_DIR/kotlinc/bin"
add_to_path "$KOTLIN_BIN_PATH"
echo "✅ Kotlin 编译器配置完毕"

# ==============================
# 7. 安装 Go 编译器
# ==============================
echo "📦 [5/5] 正在处理 Go 编译器..."

if [ ! -d "go" ]; then
    echo "⬇️ 未检测到缓存，正在获取最新稳定版 Go..."
    # 获取最新稳定版的版本号，例如 "go1.23.1"
    GO_VERSION=$(curl -sL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version')
    
    if [ -z "$GO_VERSION" ] || [ "$GO_VERSION" == "null" ]; then
        echo "❌ 无法获取 Go 最新版本号"
        exit 1
    fi
    
    # 构建 amd64 专用的下载链接
    GO_TARBALL="${GO_VERSION}.linux-amd64.tar.gz"
    GO_URL="https://go.dev/dl/${GO_TARBALL}"
    
    echo "正在下载 $GO_VERSION ..."
    curl -fSL "$GO_URL" -o go.tar.gz
    tar -xzf go.tar.gz
    rm go.tar.gz
else
    echo "✅ 发现已缓存的 go 目录"
fi

GO_BIN_PATH="$TOOLS_DIR/go/bin"
add_to_env "GOROOT" "$TOOLS_DIR/go"
add_to_path "$GO_BIN_PATH"
echo "✅ Go 编译器配置完毕"

# ==============================
# 8. 完成提示
# ==============================
echo "========================================="
echo "🎉 所有依赖环境配置完毕！"
echo "========================================="

if ! is_ci; then
    echo ""
    echo "💡 提示：您正在【本地环境】运行。"
    echo "由于本地 Shell 重启后环境变量会丢失，请执行以下命令使配置在当前终端生效："
    echo ""
    echo "   👉 source $ENV_FILE"
    echo ""
fi