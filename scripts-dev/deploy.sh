#!/usr/bin/env bash
# deploy.sh - 部署模块到设备（开发迭代用，无需重启）
# 用法: bash scripts-dev/deploy.sh [push|config|start|stop|status|log|all]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$ROOT/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB=adb
MOD_REMOTE=/data/adb/modules/ksuclash
DATA_REMOTE=/data/adb/ksuclash

adb_shell() { "$ADB" shell "su -c '$1'" </dev/null; }

# Git Bash 下 adb push 的本地参数需要 Windows 形式路径
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

push_module() {
    echo ">> push module"
    "$ADB" push "$(winpath "$ROOT/module")" /data/local/tmp/ksuclash_stage > /dev/null </dev/null
    adb_shell "rm -rf $MOD_REMOTE && mkdir -p $MOD_REMOTE"
    adb_shell "cp -a /data/local/tmp/ksuclash_stage/. $MOD_REMOTE/"
    adb_shell "rm -rf /data/local/tmp/ksuclash_stage"
    adb_shell "chown -R 0.0 $MOD_REMOTE"
    adb_shell "find $MOD_REMOTE -type d -exec chmod 755 {} +"
    adb_shell "find $MOD_REMOTE -type f -exec chmod 644 {} +"
    adb_shell "chmod 755 $MOD_REMOTE/scripts/* $MOD_REMOTE/scripts/clashctl $MOD_REMOTE/*.sh $MOD_REMOTE/bin/mihomo"
    echo ">> done"
}

push_config() {
    echo ">> push user config (workspace clash.yaml -> $DATA_REMOTE/config.yaml)"
    "$ADB" push "$(winpath "$ROOT/clash.yaml")" /data/local/tmp/ksuclash_user.yaml > /dev/null </dev/null
    adb_shell "mkdir -p $DATA_REMOTE/state $DATA_REMOTE/logs $DATA_REMOTE/cache"
    adb_shell "cp -f /data/local/tmp/ksuclash_user.yaml $DATA_REMOTE/config.yaml && rm -f /data/local/tmp/ksuclash_user.yaml"
    echo ">> done"
}

case "${1:-all}" in
    push)   push_module ;;
    config) push_config ;;
    start)  adb_shell "sh $MOD_REMOTE/scripts/clashctl start" ;;
    stop)   adb_shell "sh $MOD_REMOTE/scripts/clashctl stop" ;;
    status) adb_shell "sh $MOD_REMOTE/scripts/clashctl status" ;;
    log)    adb_shell "tail -n 30 $DATA_REMOTE/logs/mihomo.log" ;;
    all)    push_module; push_config; adb_shell "sh $MOD_REMOTE/scripts/clashctl start" ;;
    *) echo "usage: deploy.sh [push|config|start|stop|status|log|all]"; exit 1 ;;
esac
