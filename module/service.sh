#!/system/bin/sh
# service.sh - 开机启动入口（不阻塞，后台拉起）
MODDIR="/data/adb/modules/ksuclash"
SCR="$MODDIR/scripts"

# 引入 KSU busybox 到 PATH（awk 等）
[ -d /data/adb/ksu/bin ] && PATH="/data/adb/ksu/bin:$PATH"
export PATH

{
    # 等待系统启动完成（最多 3 分钟）
    _i=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$_i" -lt 90 ]; do
        sleep 2
        _i=$((_i + 1))
    done
    # 给 netd/网络栈留出稳定时间
    sleep 5

    # 等待基础网络就绪（最多 90s），确保 mihomo 启动时能拉取订阅/规则
    _j=0
    while [ "$_j" -lt 30 ]; do
        if ping -c1 -W1 223.5.5.5 > /dev/null 2>&1; then
            break
        fi
        sleep 3
        _j=$((_j + 1))
    done

    mkdir -p /data/adb/ksuclash/state /data/adb/ksuclash/logs 2>/dev/null

    if [ -f /data/adb/ksuclash/state/enabled ]; then
        [ "$(cat /data/adb/ksuclash/state/enabled 2>/dev/null)" != "0" ] && \
            sh "$SCR/clashctl" start >> /data/adb/ksuclash/logs/boot.log 2>&1
    else
        # 全新安装：默认启用
        echo 1 > /data/adb/ksuclash/state/enabled 2>/dev/null
        sh "$SCR/clashctl" start >> /data/adb/ksuclash/logs/boot.log 2>&1
    fi
} > /dev/null 2>&1 &

# 幂等安装/更新辅助 APK（磁贴+通知快捷入口），失败不影响主流程
{
    sleep 20
    if ! pm path io.github.ksuclash.control > /dev/null 2>&1; then
        pm install -r "$MODDIR/bin/MihomoControl.apk" > /dev/null 2>&1
    fi
} > /dev/null 2>&1 &

exit 0
