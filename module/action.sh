#!/system/bin/sh
# action.sh - KernelSU 管理器「Action」按钮：切换启停 + 输出状态
MODDIR="/data/adb/modules/ksuclash"
SCR="$MODDIR/scripts"
[ -d /data/adb/ksu/bin ] && PATH="/data/adb/ksu/bin:$PATH"
export PATH

echo "== KSU Clash (mihomo) =="
sh "$SCR/clashctl" status | head -1

if [ -f /data/adb/ksuclash/state/panic ]; then
    echo "! 熔断状态: $(cat /data/adb/ksuclash/state/panic)"
    echo "  执行恢复: su -c 'sh $SCR/clashctl resume'"
fi

if sh "$SCR/clashctl" status | grep -q '^state=on'; then
    echo ">> 当前运行中，正在停止..."
    sh "$SCR/clashctl" stop
else
    echo ">> 当前已停止，正在启动..."
    sh "$SCR/clashctl" start
fi

echo "== 操作后状态 =="
sh "$SCR/clashctl" status
echo ""
echo "面板: $(sh "$SCR/clashctl" panel)"
