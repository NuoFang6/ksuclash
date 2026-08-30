#!/system/bin/sh
# uninstall.sh - 彻底清理，不留残留
MODDIR="/data/adb/modules/ksuclash"

# 停核心与看门狗
pkill -f "ksuclash/runtime.yaml" 2>/dev/null
pkill -f "ksuclash/scripts/watchdog.sh" 2>/dev/null
for p in /data/adb/ksuclash/state/*.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null
done
sleep 1
pkill -9 -f "ksuclash/runtime.yaml" 2>/dev/null

# 移除辅助 App（通知随卸载消失）
pm uninstall io.github.ksuclash.control > /dev/null 2>&1

# 删除全部持久化数据
rm -rf /data/adb/ksuclash

exit 0
