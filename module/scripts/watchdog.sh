#!/system/bin/sh
# watchdog.sh - 轻量看门狗：进程守护 + 崩溃熔断 + 日志轮转
# 由 clashctl start 启动；30s 周期，纯 sleep 轮询，功耗可忽略。
# CRASH_FILE 格式: "<count> <first_crash_ts>"，仅统计 CRASH_WINDOW 秒内的连续崩溃。

. /data/adb/modules/ksuclash/scripts/common.sh

INTERVAL=30
MAX_CRASH=3          # 窗口内崩溃次数上限，达到即熔断
CRASH_WINDOW=600     # 秒

crash_bump() {  # $1=now; 输出窗口内累计次数
    _now="$1"
    _n=0; _ts=0
    set -- $(cat "$CRASH_FILE" 2>/dev/null)
    [ -n "$1" ] && _n="$1"
    [ -n "$2" ] && _ts="$2"
    _age=$((_now - _ts))
    if [ "$_ts" -eq 0 ] || [ "$_age" -gt "$CRASH_WINDOW" ]; then
        _n=0; _ts=$_now
    fi
    _n=$((_n + 1))
    $BB echo "$_n $_ts" > "$CRASH_FILE"
    $BB echo "$_n"
}

cleanup_self() {  # 仅当 pidfile 归属自己时删除
    [ "$(cat "$WDPID_FILE" 2>/dev/null)" = "$$" ] && $BB rm -f "$WDPID_FILE"
    exit 0
}
trap 'cleanup_self' INT TERM

log "watchdog started (pid $$)"
$BB echo $$ > "$WDPID_FILE" 2>/dev/null

while :; do
    sleep $INTERVAL

    # 用户已停止（核心 pidfile 消失）→ 看门狗退出
    [ -f "$PID_FILE" ] || { log "watchdog exit (no pidfile)"; cleanup_self; }
    _p=$(cat "$PID_FILE" 2>/dev/null)
    [ -z "$_p" ] && { log "watchdog exit (empty pidfile)"; cleanup_self; }

    # 日志轮转
    rotate_log

    if ! kill -0 "$_p" 2>/dev/null; then
        # 核心已死亡
        _now=$(date +%s)
        _n=$(crash_bump "$_now")
        log "core died (window count=$_n)"

        if [ "$_n" -ge "$MAX_CRASH" ]; then
            echo "窗口内崩溃${_n}次，已自动熔断 $(date "+%m-%d %H:%M")" > "$PANIC_FILE"
            $BB rm -f "$PID_FILE"
            set_tile panic
            log "PANIC: too many crashes, auto-disabled"
            echo "[watchdog] 连续崩溃，已熔断停止" >> "$LOG_FILE"
            cleanup_self
        fi

        log "auto restart core (attempt $_n)"
        set_tile starting
        _out=$(sh "$SCR_DIR/clashctl" start 2>&1)
        _rc=$?
        echo "$_out" | tail -3 >> "$LOG_FILE"
        if [ $_rc -ne 0 ]; then
            log "restart failed rc=$_rc"
            _n2=$(crash_bump "$(date +%s)")
            if [ "$_n2" -ge "$MAX_CRASH" ]; then
                echo "启动反复失败，已自动熔断 $(date "+%m-%d %H:%M")" > "$PANIC_FILE"
                set_tile panic
                log "PANIC: restart keeps failing"
                cleanup_self
            fi
        fi
        continue
    fi

    # 进程活着但 tun 网卡丢失（sing-tun 异常）→ 连续2次则重启
    if ! $BB ls /sys/class/net 2>/dev/null | $BB grep -qiE '^(Meta|mihomo)$'; then
        _tm=$(cat "$STATE_DIR/.tunmiss" 2>/dev/null)
        case "$_tm" in ''|*[!0-9]*) _tm=0 ;; esac
        _tm=$((_tm + 1))
        $BB echo "$_tm" > "$STATE_DIR/.tunmiss"
        log "tun iface missing ($_tm)"
        if [ "$_tm" -ge 2 ]; then
            $BB rm -f "$STATE_DIR/.tunmiss"
            log "restarting core due to missing tun"
            kill "$_p" 2>/dev/null
            sleep 2
            _out=$(sh "$SCR_DIR/clashctl" start 2>&1)
            echo "$_out" | tail -2 >> "$LOG_FILE"
        fi
    else
        $BB rm -f "$STATE_DIR/.tunmiss" 2>/dev/null
    fi
done
