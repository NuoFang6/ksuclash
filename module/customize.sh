#!/system/bin/sh
# customize.sh - KernelSU 安装脚本
SKIPUNZIP=0

# ksud 在 /dev/tmp 执行 customize.sh 时文件可能已被移动到 modules_update，
# 故 MODDIR 必须探测真实目录，不能用 $PWD。
MODDIR="/data/adb/modules_update/ksuclash"
[ -f "$MODDIR/module.prop" ] || MODDIR="$PWD"
[ -f "$MODDIR/module.prop" ] || MODDIR="/data/adb/modules/ksuclash"
ui_print "- module dir: $MODDIR"
DATA_DIR="/data/adb/ksuclash"

ui_print "- KSU Clash (mihomo) 安装中"

# 仅支持 arm64
if [ "$ARCH" != "arm64" ]; then
    ui_print "! 不支持的架构: $ARCH（本模块仅提供 arm64）"
    abort
fi

# 权限
set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm_recursive "$MODDIR/scripts" 0 0 0755 0755
set_perm_recursive "$MODDIR/bin" 0 0 0755 0755
set_perm_recursive "$MODDIR/webroot" 0 0 0755 0644
set_perm_recursive "$MODDIR/ui" 0 0 0755 0644
set_perm "$MODDIR/service.sh" 0 0 0755
set_perm "$MODDIR/uninstall.sh" 0 0 0755
set_perm "$MODDIR/action.sh" 0 0 0755

# 用户数据目录（保留用户配置，升级不覆盖）
mkdir -p "$DATA_DIR/state" "$DATA_DIR/logs" "$DATA_DIR/cache"
# zashboard 面板复制到数据目录（mihomo external-ui 安全限制：仅允许 -d 主目录内的路径）
rm -rf "$DATA_DIR/ui"
cp -r "$MODDIR/ui" "$DATA_DIR/ui"
if [ ! -f "$DATA_DIR/config.yaml" ]; then
    cp -f "$MODDIR/config.default.yaml" "$DATA_DIR/config.yaml"
    ui_print "- 已生成默认配置模板: $DATA_DIR/config.yaml"
    ui_print "  请填入你的节点/订阅后启动"
else
    ui_print "- 保留现有用户配置"
fi
[ -f "$DATA_DIR/state/enabled" ] || echo 1 > "$DATA_DIR/state/enabled"

# 安装辅助 APK（快捷磁贴 + 通知操作；失败不阻塞）
if [ -f "$MODDIR/bin/MihomoControl.apk" ]; then
    if pm install -r "$MODDIR/bin/MihomoControl.apk" > /dev/null 2>&1; then
        ui_print "- 已安装快捷控制 App（控制中心磁贴 + 通知按钮）"
    else
        ui_print "! 控制 App 安装失败（开机后会自动重试）"
    fi
fi

ui_print ""
ui_print "  快速上手:"
ui_print "  1. 配置: /data/adb/ksuclash/config.yaml"
ui_print "  2. 启停: 控制中心磁贴 / 通知按钮 / 管理器Action"
ui_print "  3. 面板: 管理器 WebUI 入口 → http://127.0.0.1:9090/ui/"
ui_print "  4. CLI : sh /data/adb/modules/ksuclash/scripts/clashctl"
ui_print ""
