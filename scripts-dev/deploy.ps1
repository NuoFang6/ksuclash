# deploy.ps1 - 部署模块到设备（PowerShell 编排，Git Bash 下 adb 有挂起问题）
# 用法: powershell -File scripts-dev/deploy.ps1 [push|config|start|stop|status|log|all]
param([string]$Action = "all")
$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot | Split-Path
$Adb = Join-Path $Root "platform-tools\adb.exe"
if (-not (Test-Path $Adb)) { $Adb = "adb" }
$ModRemote = "/data/adb/modules/ksuclash"
$DataRemote = "/data/adb/ksuclash"

function Su([string]$cmd) {
    & $Adb shell "su -c '$cmd'" 2>&1 | ForEach-Object { "$_" }
}
function PushModule {
    ">> push module"
    & $Adb push "$Root\module" /data/local/tmp/ksuclash_stage | Out-Null
    Su "rm -rf $ModRemote && mkdir -p $ModRemote" | Out-Null
    Su "cp -a /data/local/tmp/ksuclash_stage/. $ModRemote/" | Out-Null
    Su "rm -rf /data/local/tmp/ksuclash_stage" | Out-Null
    Su "chown -R 0.0 $ModRemote" | Out-Null
    Su "find $ModRemote -type d -exec chmod 755 {} +" | Out-Null
    Su "find $ModRemote -type f -exec chmod 644 {} +" | Out-Null
    Su "chmod 755 $ModRemote/scripts/* $ModRemote/*.sh $ModRemote/bin/mihomo" | Out-Null
    # 同步 zashboard 到数据目录（external-ui 限制）并重算 runtime + 面板配置
    Su "mkdir -p $DataRemote/state $DataRemote/logs $DataRemote/cache && rm -rf $DataRemote/ui" | Out-Null
    Su "cp -r $ModRemote/ui $DataRemote/ui && sh $ModRemote/scripts/patch_config.sh" | Out-Null
    ">> done"
}
function PushConfig {
    ">> push user config"
    & $Adb push "$Root\clash.yaml" /data/local/tmp/ksuclash_user.yaml | Out-Null
    Su "mkdir -p $DataRemote/state $DataRemote/logs $DataRemote/cache" | Out-Null
    Su "cp -f /data/local/tmp/ksuclash_user.yaml $DataRemote/config.yaml && rm -f /data/local/tmp/ksuclash_user.yaml" | Out-Null
    Su "rm -f $DataRemote/runtime.yaml" | Out-Null
    ">> done"
}

switch ($Action) {
    "push"   { PushModule }
    "config" { PushConfig }
    "start"  { Su "sh $ModRemote/scripts/clashctl start" }
    "stop"   { Su "sh $ModRemote/scripts/clashctl stop" }
    "status" { Su "sh $ModRemote/scripts/clashctl status" }
    "log"    { Su "tail -n 40 $DataRemote/logs/mihomo.log" }
    "all"    { PushModule; PushConfig; Su "sh $ModRemote/scripts/clashctl start" }
    default  { "usage: deploy.ps1 [push|config|start|stop|status|log|all]" }
}
