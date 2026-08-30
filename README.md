# KSU Clash (mihomo)

KernelSU / ReSukiSU 模块：以 **TUN 模式**（非 Android VpnService）运行 [mihomo](https://github.com/MetaCubeX/mihomo)，
适配 WiFi / 蜂窝自动切换，含看门狗熔断保护、控制中心磁贴、通知快捷按钮、zashboard 面板与悬浮控制窗，卸载无残留。

## 特性

- **TUN 接管**：mihomo 自带 `auto-route`（ip rule 策略路由）+ `auto-detect-interface`（netlink 监听换网自动重绑出站），模块侧**零 iptables**；核心退出后路由随 tun 消失，系统自动回到直连，天然故障安全。
- **最小侵入配置**：你的配置文件 `/data/adb/ksuclash/config.yaml` **永不被修改**；启动时生成派生的 `runtime.yaml`，仅在缺失 `tun.enable` / `dns.enable` / `external-controller` / `external-ui` 时补齐（头部注释可审计），其余逐字节保留。
- **快捷路径**：
  - 控制中心**磁贴**（点按启停，长按进控制台）
  - 开机**常驻通知**（暂停切直连 / 重启核心 / 打开面板；静态通知，无前台服务零耗电）
  - 管理器 **Action 按钮**（启停切换 + 状态）
  - 管理器 **WebUI 引导页**（状态 + 全部操作 + 导入配置）
  - **悬浮面板**（注入 zashboard：启动/停止/重启核心 + 模式切换；浏览器访问自动降级为仅 API 操作）
- **看门狗熔断**：核心死亡自动拉起（30s 周期）；**10 分钟窗口内崩溃 ≥3 次自动熔断**（panic 停止并禁止拉起，防止死循环），磁贴/通知显示熔断态，手动恢复即 `clashctl resume`。
- **zashboard 直登**：`clashctl panel` 生成参数化 URL（secret 自动编码），管理器/浏览器打开即自动登录，无需手动填密钥。
- **省电**：无常驻前台服务、无轮询网络；mihomo 空闲 CPU ≈0（实测 ~3% 采样噪声）。

## 安装

1. 刷入 `ksuclash-*.zip`（管理器刷入或 `ksud module install xxx.zip`）。
2. 首次安装会自动生成配置模板并安装控制 App（`io.github.ksuclash.control`）。
3. 将你原有的 `clash.yaml` 放到 `/data/adb/ksuclash/config.yaml`（`adb push` 后 su 拷贝，或管理器 WebUI 引导页「导入配置文件」）。
4. 在管理器「超级用户」中给 **KSU Clash**（控制 App）授权 root（一次性）。
5. 从控制中心添加 **Mihomo 代理** 磁贴。

## 使用

| 入口 | 操作 |
|---|---|
| 磁贴 | 点按=启停切换；长按=控制台 App |
| 通知 | 暂停(直连)/重启核心/面板；点正文进 App |
| 管理器 WebUI | 状态、启停、模式、导入配置、打开面板 |
| CLI | `sh /data/adb/modules/ksuclash/scripts/clashctl {start\|stop\|restart\|reload\|toggle\|resume\|enable\|disable\|status\|mode rule\|panel\|log}` |
| 面板 | `clashctl panel` 输出的 URL（管理器 WebUI 或浏览器均可） |

## 目录

```
/data/adb/modules/ksuclash/     模块本体（bin/scripts/ui/webroot）
/data/adb/ksuclash/
  ├─ config.yaml                你的配置（唯一编辑对象）
  ├─ runtime.yaml               派生运行时配置（自动生成）
  ├─ ui/                        zashboard（含 panel-config.js，随启动按你的 secret 生成）
  ├─ logs/ state/ cache/
```

## 故障与恢复

- 启动失败 / 反复崩溃 → 自动熔断（磁贴显示"已熔断"），排查 `logs/mihomo.log` 后 `clashctl resume`。
- 配置语法错误会在启动前被 `mihomo -t` 拦截，不会带病上线。
- 卸载模块：自动停核心、删 `/data/adb/ksuclash`、卸载控制 App、通知随 App 消失，**无任何系统残留**。

## CI

`.github/workflows/build-module.yml`：每次构建实时拉取最新 mihomo release / zashboard main（FONT=none 减小体积），
注入悬浮面板、aapt2+d8 手工流水线构建签名 APK、打包模块 zip；每周定时自动跟进上游。打 tag 自动发 Release。

## 本地开发

```bash
bash scripts-dev/deploy.ps1 ...        # 或 helper-apk/build-apk.sh 构建 APK
node scripts-dev/patch-ui.mjs zashboard/dist module   # 打包 zashboard + 注入悬浮面板
```

依赖：Node/pnpm（zashboard）、JDK17+（APK）、platform-tools（adb）。
