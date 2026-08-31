#!/system/bin/sh
# customize.sh - SU Clash (mihomo) 安装/升级脚本
#
# 由 ksud installer.sh source 执行（非子进程），执行前安装器已完成：
#   - 全部模块文件已解压到 $MODPATH（SKIPUNZIP=0）
#   - 默认权限：目录 0755 / 文件 0644
#   - 预置变量：$MODPATH $TMPDIR $ZIPFILE $ARCH $API 等
# 数据目录 /data/adb/suclash 不在模块目录内，升级时自动保留。

SKIPUNZIP=0

DATA_DIR="/data/adb/suclash"

# 多架构内核选择
# 约定：bin/mihomo 为默认(arm64)内核；其它架构以 bin/mihomo.<tag> 形式随包附带，
# 安装时按 $ARCH 选用其一并规范命名为 bin/mihomo，下游统一引用 bin/mihomo。
# tag 映射（KernelSU 与 Magisk 的 $ARCH 命名不同，均兼容）：
#   arm64 -> 默认      arm -> armv7      x86_64/x64 -> amd64      x86 -> 386
case "$ARCH" in
    arm64)  SEL="" ;;
    arm)    SEL="armv7" ;;
    x86_64|x64) SEL="amd64" ;;
    x86)    SEL="386" ;;
    *)      abort "! 不支持的架构: $ARCH" ;;
esac
if [ -n "$SEL" ]; then
    # 非 arm64：必须附带对应架构二进制，绝不静默回退到默认(arm64)内核
    [ -f "$MODPATH/bin/mihomo.$SEL" ] || abort "! 本模块未附带 $ARCH 内核（缺少 bin/mihomo.$SEL）"
    mv -f "$MODPATH/bin/mihomo.$SEL" "$MODPATH/bin/mihomo"
    # 清理其它架构二进制，避免占用空间
    for _b in "$MODPATH"/bin/mihomo.*; do
        [ -e "$_b" ] || continue
        [ "$(basename "$_b")" = "mihomo.$SEL" ] || rm -f "$_b"
    done
else
    [ -f "$MODPATH/bin/mihomo" ] || abort "! 缺少 arm64 内核二进制（bin/mihomo）"
    for _b in "$MODPATH"/bin/mihomo.*; do [ -e "$_b" ] && rm -f "$_b"; done
fi

# 管理器二进制 suclash_helper 同样按架构选择（与 mihomo 同一约定）
if [ -n "$SEL" ]; then
    [ -f "$MODPATH/bin/suclash_helper.$SEL" ] || abort "! 本模块未附带 $ARCH 管理器（缺少 bin/suclash_helper.$SEL）"
    mv -f "$MODPATH/bin/suclash_helper.$SEL" "$MODPATH/bin/suclash_helper"
fi
for _b in "$MODPATH"/bin/suclash_helper.*; do
    [ -e "$_b" ] && rm -f "$_b"
done
[ -f "$MODPATH/bin/suclash_helper" ] || abort "! 缺少管理器二进制（bin/suclash_helper）"

MOD_VER=$(grep_prop version "$MODPATH/module.prop")
ui_print "- SU Clash (mihomo) $MOD_VER 安装中"

# 升级说明：更新只写入 modules_update/，旧目录 /data/adb/modules/<id> 原样保留并打
# update 标记，重启时才由 ksud 应用更新。此期间旧 mihomo 继续从旧目录运行（代理不中断），
# 与新文件零冲突，所以这里不需要也不应该停掉运行中的实例。

# 权限（补可执行位）
# 安装器默认只给 system/bin 等目录 0755，模块根下的可执行文件需手动设置
set_perm "$MODPATH/service.sh"   0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/action.sh"    0 0 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm "$MODPATH/bin/mihomo" 0 0 0755
set_perm "$MODPATH/bin/suclash_helper" 0 0 0755

# 用户数据目录（升级保留，仅补齐缺失部分）
mkdir -p "$DATA_DIR/state" "$DATA_DIR/logs" "$DATA_DIR/cache"

# zashboard 面板复制到数据目录（mihomo external-ui 安全限制：仅允许 -d 主目录内路径）
rm -rf "$DATA_DIR/ui"
cp -a "$MODPATH/ui" "$DATA_DIR/ui"

# 用户配置：仅首次生成，升级不覆盖
if [ ! -f "$DATA_DIR/config.yaml" ]; then
    cp -f "$MODPATH/config.default.yaml" "$DATA_DIR/config.yaml"
    ui_print "- 已生成默认配置: $DATA_DIR/config.yaml"
    ui_print "  请填入你的节点/订阅后启动"
else
    ui_print "- 保留现有用户配置"
fi

# 首次安装默认启用
[ -f "$DATA_DIR/state/enabled" ] || echo 1 > "$DATA_DIR/state/enabled"

# 辅助 App（快捷磁贴 + 通知操作）：不在安装期 pm install。
# 此刻旧模块仍在运行（更新要到重启才生效），现在装新 App 会与运行中的旧磁贴/通知脱节；
# 改为记录新 APK 指纹，重启后由 service.sh 比对指纹并安装/更新。
if [ -f "$MODPATH/bin/MihomoControl.apk" ]; then
    md5sum "$MODPATH/bin/MihomoControl.apk" 2>/dev/null | awk '{print $1}' \
        > "$DATA_DIR/state/apk.md5"
    ui_print "- 控制 App 将在重启后自动安装/更新"
fi

ui_print ""
ui_print "  快速上手:"
ui_print "  1. 配置: /data/adb/suclash/config.yaml"
ui_print "  2. 启停: 控制中心磁贴 / 通知按钮 / 管理器Action"
ui_print "  3. 面板: 管理器 WebUI 入口 → http://127.0.0.1:9090/ui/"
ui_print "  4. CLI : sh /data/adb/modules/suclash/scripts/clashctl"
ui_print ""
