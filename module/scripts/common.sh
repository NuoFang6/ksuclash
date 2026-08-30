#!/system/bin/sh
# common.sh - KSU Clash 共享路径与工具函数（被其他脚本 source）

MODDIR="/data/adb/modules/ksuclash"
DATA_DIR="/data/adb/ksuclash"
BIN_DIR="$MODDIR/bin"
SCR_DIR="$MODDIR/scripts"
UI_DIR="$MODDIR/ui"

STATE_DIR="$DATA_DIR/state"
LOG_DIR="$DATA_DIR/logs"
DATA_UI_DIR="$DATA_DIR/ui"
USER_CFG="$DATA_DIR/config.yaml"
RUNTIME_CFG="$DATA_DIR/runtime.yaml"
LOG_FILE="$LOG_DIR/mihomo.log"
LOG_MAX=$((8 * 1024 * 1024))

PID_FILE="$STATE_DIR/mihomo.pid"
WDPID_FILE="$STATE_DIR/watchdog.pid"
ENABLED_FILE="$STATE_DIR/enabled"
PANIC_FILE="$STATE_DIR/panic"
CRASH_FILE="$STATE_DIR/crashes"
TILE_FILE="$STATE_DIR/tile"

API_ADDR="127.0.0.1:9090"
CTRL_PKG="io.github.ksuclash.control"

# busybox（KernelSU 自带，含 awk/wget/nc 等完整 applet）
if [ -x /data/adb/ksu/bin/busybox ]; then
    BB=/data/adb/ksu/bin/busybox
elif [ -x /data/adb/ksud/bin/busybox ]; then
    BB=/data/adb/ksud/bin/busybox
else
    BB=busybox
fi

log() { $BB echo "[$($BB date '+%m-%d %H:%M:%S')] $*" >> "$DATA_DIR/module.log" 2>/dev/null; }

# 读取 runtime.yaml 中的 secret（可能带引号与行尾注释）
get_secret() {
    $BB awk '{
        line=$0
        sub(/[[:space:]]*#.*$/, "", line)
        if (line ~ /^secret:/) {
            sub(/^secret:[[:space:]]*/, "", line)
            gsub(/^["'\'']|["'\'']$/, "", line)
            print line
            exit
        }
    }' "$RUNTIME_CFG" 2>/dev/null
}

# 任意方法调用本机 clash API。用法: api GET /version | api PATCH /configs '{"mode":"direct"}'
api() {
    _m="$1"; _p="$2"; _b="$3"
    _s=$(get_secret)
    _h=""
    [ -n "$_s" ] && _h="Authorization: Bearer $_s"
    _len=0
    [ -n "$_b" ] && _len=$($BB echo -n "$_b" | $BB wc -c)
    {
        $BB printf '%s %s HTTP/1.0\r\nHost: %s\r\n' "$_m" "$_p" "$API_ADDR"
        [ -n "$_h" ] && $BB printf '%s\r\n' "$_h"
        $BB printf 'Content-Type: application/json\r\nConnection: close\r\n'
        $BB printf 'Content-Length: %s\r\n\r\n' "$_len"
        [ -n "$_b" ] && $BB printf '%s' "$_b"
    } | timeout 6 $BB nc "$API_ADDR" 2>/dev/null | $BB sed '1s/^[^ ]* \([0-9][0-9][0-9]\).*/HTTP_CODE:\1/' | $BB awk '/^HTTP_CODE:/{next} {print}'
}

api_code() {  # 仅返回 HTTP 状态码
    _m="$1"; _p="$2"; _b="$3"
    _s=$(get_secret)
    _h=""
    [ -n "$_s" ] && _h="Authorization: Bearer $_s"
    _len=0
    [ -n "$_b" ] && _len=$($BB echo -n "$_b" | $BB wc -c)
    {
        $BB printf '%s %s HTTP/1.0\r\nHost: %s\r\n' "$_m" "$_p" "$API_ADDR"
        [ -n "$_h" ] && $BB printf '%s\r\n' "$_h"
        $BB printf 'Content-Type: application/json\r\nConnection: close\r\nContent-Length: %s\r\n\r\n' "$_len"
        [ -n "$_b" ] && $BB printf '%s' "$_b"
    } | timeout 6 $BB nc "$API_ADDR" 2>/dev/null | $BB head -1
}

# 核心进程 pid（-1 表示未运行）
core_pid() {
    _p="$($BB pgrep -f "$RUNTIME_CFG" 2>/dev/null | $BB head -1)"
    [ -z "$_p" ] && _p="-1"
    $BB echo "$_p"
}

is_running() {
    [ "$(core_pid)" != "-1" ]
}

ensure_dirs() {
    $BB mkdir -p "$STATE_DIR" "$LOG_DIR" "$DATA_DIR/cache" 2>/dev/null
}

# 写磁贴/通知可读状态文件: on|off|starting|stopping|panic
set_tile() {
    $BB echo "$1" > "$TILE_FILE" 2>/dev/null
}

# 日志超限轮转（保留一份 .old）
rotate_log() {
    [ -f "$LOG_FILE" ] || return 0
    _sz=$(wc -c < "$LOG_FILE" 2>/dev/null)
    case "$_sz" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_sz" -gt "$LOG_MAX" ] && $BB mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null
    return 0
}
