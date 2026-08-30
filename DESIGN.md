# KSU Clash (mihomo) 模块设计

KernelSU 模块，以 **TUN（非 VpnService）** 方式运行 mihomo，目标：稳定、省电、各 App 兼容、卸载无残留。

## 1. 总体架构

```
┌──────────────────────────  Android (root via KernelSU)  ──────────────────────────┐
│                                                                                   │
│  App 流量 ──(policy route: table 2022, rule pref 9000)──► tun ──► mihomo 核心      │
│   WiFi(wlan0) / 蜂窝(ccmniX) ◄── SO_MARK+绑定网卡 出站（auto-detect-interface）     │
│                                                                                   │
│  mihomo (官方 android-arm64, Go)                                                   │
│   ├─ TUN 栈: system TCP + gVisor UDP (stack: system / mixed, mtu 1500)             │
│   ├─ DNS 劫持: tun dns-hijack 0.0.0.0:53 → 内置 DNS (fake-ip)                      │
│   ├─ 外部控制器 127.0.0.1:9090 + external-ui → zashboard（同源, 无CORS/混合内容问题）│
│   └─ 连接出站绑定默认网卡, netlink 监听 WiFi/蜂窝切换自动重绑                        │
│                                                                                   │
│  /data/adb/modules/ksuclash/   模块本体（升级时整体替换）                            │
│  /data/adb/ksuclash/          用户数据（配置/日志/状态, 卸载时清除）                  │
└───────────────────────────────────────────────────────────────────────────────────┘
```

**核心原则：路由与出站全部交给 mihomo 自身的 auto-route + auto-detect-interface
（sing-tun: ip rule/fwmark 策略路由），模块侧不写任何 iptables/nftables 规则。**
进程退出 → tun 消失 → 内核自动回收路由 → 系统回到直连，天然"故障安全"。

## 2. 目录与数据

| 路径 | 作用 | 生命周期 |
|---|---|---|
| `/data/adb/modules/ksuclash/` | 模块：二进制/脚本/webroot/ui(zashboard)/APK | 安装/更新/卸载由管理器管理 |
| `/data/adb/ksuclash/config.yaml` | **用户配置（唯一编辑对象，模块永不改写）** | 卸载时删除 |
| `/data/adb/ksuclash/runtime.yaml` | 由用户配置派生的运行时配置（含必要补丁） | 每次启动重算 |
| `/data/adb/ksuclash/{logs,state,cache}` | 日志/状态/geo与规则缓存 | 卸载时删除 |
| 通知/磁贴辅助 APK `io.github.ksuclash.control` | 快捷磁贴+常驻通知 | 卸载时 `pm uninstall` |

## 3. 配置处理（最小侵入）

- 用户 `config.yaml` 永不被修改；启动时生成 `runtime.yaml` = 用户配置 + **仅缺失时**补充：
  1. `tun.enable: true`（若 tun 段缺失/未启用 → 补齐默认 tun 段）
  2. `dns.enable: true`（若被关闭；TUN+dns-hijack 必需）
  3. `external-controller`/`external-ui`（缺失时补，WebUI 必需；已有则尊重用户值）
  4. 其余一切参数（端口/模式/规则/节点/DNS细节）原样保留。
- 应用过的补丁写进 runtime.yaml 头部注释与日志，可审计。

## 4. 快捷路径（启停）

1. **控制中心磁贴**（QS Tile）：点按=启/停切换，长按进控制 App。磁贴状态由 root 读状态文件。
2. **常驻通知**：开机后由辅助 App post（无前台服务、无唤醒锁、零耗电），
   动作按钮：暂停(切直连)/恢复(切规则)/重启核心，点正文进 App，App 内含全部操作。
3. **KernelSU 管理器 Action 按钮**（action.sh）：切换启停 + 状态输出。
4. **WebUI 悬浮面板**：见 §5。

辅助 App 以 `su -c clashctl …` 调用模块 CLI，首次需在管理器里放行一次 root。

## 5. WebUI

- zashboard 由 **mihomo external-ui** 直接托管：`http://127.0.0.1:9090/ui/`
  —— 与 clash API 同源，无 CORS、无混合内容问题（KSU 管理器 WebUI 源是 https://mui.kernelsu.org，
  不能直接 fetch http API，因此引导页只做导航与 root 操作）。
- 模块 `webroot/index.html`（管理器"WebUI"入口）：状态卡 + 启停/重启 + 打开面板按钮（location 跳转）。
- **悬浮面板**（构建时注入 zashboard 的 index.html）：可拖拽气泡，含核心级操作
  （启动/停止/重启，经 `window.ksu.exec` root 桥）+ API 级操作（规则/全局/直连模式切换）；
  浏览器直接访问时自动降级为仅 API 操作。

## 6. 稳定性与故障策略

- **防环路**：mihomo 出站 socket 带 fwmark + 绑定物理网卡（sing-tun 策略路由排除自身）；
  模块不引入任何转发类规则，无回环路径。启动后校验 tun 网卡与 API 就绪。
- **看门狗**（30s 周期，纯 sh，开销可忽略）：
  - 核心死亡 → 自动拉起（带退避）；**10 分钟内崩溃 ≥3 次 → 熔断（panic）**：
    停止核心、禁止自启、状态标记 panic，等用户手动恢复，杜绝死循环。
  - "运行中"但 tun 网卡消失 → 连续 2 次判定后重启核心。
  - 日志超限自动轮转。
- **重启风暴保护**：service.sh 启动失败只重试有限次，绝不影响系统启动。
- **免重启部署**：所有启停经 clashctl，无需重启手机。

## 7. 省电设计

- 无常驻前台服务、无轮询网络 API；看门狗为 30s 一次的 sh 睡眠循环（µW 级）。
- mihomo 本体空闲近乎 0 CPU；`find-process-mode`、keep-alive 等开销项由用户配置决定，模块不覆盖。
- 通知为"静态"通知（开机 post 一次，动作按需拉起短生命周期组件）。

## 8. 无残留

- 卸载脚本：停核心 → 删 `/data/adb/ksuclash` → `pm uninstall` 辅助 App → 通知随 App 卸载消失。
- 模块不触碰系统分区、不写系统属性、不持久化任何 iptables/路由；tun/策略路由随进程消亡。
- 不使用 `post-fs-data.sh`，不挂载任何系统文件。

## 9. CI（自更新依赖）

`.github/workflows/build.yml`：每次运行实时拉取
**最新 mihomo release（android-arm64）+ 最新 zashboard 源码构建（FONT=none）+ 最新 GeoIP/metadb**，
注入悬浮面板、构建辅助 APK（aapt2/d8/apksigner 手工流水线）、打包模块 zip 传 artifact；
周计划定时任务自动跟进上游更新；打 tag 触发 Release。（当前按要求不推送。）
