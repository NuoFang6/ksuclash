#!/usr/bin/env bash
# =====================================================================
# 打包 KernelSU 模块刷机 zip
# =====================================================================

# 遇到错误立即退出
set -e

# 定位仓库根目录（从任意位置调用都正确）
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 目标架构来自 CI 矩阵（GOARCH: arm64 / amd64），本地默认 amd64
TARGET_ARCH="${GOARCH:-amd64}"

# 干净构建：避免本地残留二进制混入
rm -rf build/module
cp -r module build/module

# webroot-src 是面板源码（构建期已由 build-mihomo.sh 拷贝进 mihomo 并 go:embed），
# 运行时由 mihomo 服务端注入，不随模块分发，避免在刷机包中携带重复死文件。
rm -rf build/module/webroot-src

# module/bin 仅放本次构建产物（.gitkeep 不入包）
rm -f build/module/bin/.gitkeep
cp build/suclash_helper build/module/bin/
cp build/MihomoControl.apk build/module/bin/
cp build/mihomo build/module/bin/

# 替换 customize.sh 的架构占位符（安装时校验设备架构）
sed -i "s/__TARGET_ARCH__/${TARGET_ARCH}/" build/module/customize.sh
grep -q "^TARGET_ARCH=\"${TARGET_ARCH}\"$" build/module/customize.sh

# 刷机 zip 内容须在根层级（module.prop 位于 zip 根，ksud 直接解压到 $MODPATH）
(cd build/module && zip -qr ../module.zip .)

echo "📦 模块打包完成（架构 ${TARGET_ARCH}），产物路径: build/module.zip"
