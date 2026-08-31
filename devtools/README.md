# devtools — 开发与流水线脚本

集中存放模块开发、构建、部署、测试所用的脚本。源码与工具产物分离：
**脚本进 `devtools/`，构建产物统一进 gitignore 的 `build/`。**

## 脚本索引

| 脚本 | 职能 | 用法 |
|---|---|---|
| `deploy.sh` / `deploy.ps1` | 部署模块到设备（开发迭代，免重启） | `bash devtools/deploy.sh [push\|config\|start\|stop\|status\|log\|all]`；PowerShell 版同参数 |
| `make-module-zip.py` | 打包模块 zip（正斜杠路径 + 保留可执行位 + 排除 webroot-src） | `python3 devtools/make-module-zip.py [module-root] [output.zip]` |
| `patch-ui.mjs` | 将 zashboard 构建产物打包进模块 `ui/` 并注入悬浮面板 | `node devtools/patch-ui.mjs <zashboard-dist> <module-root>` |
| `test-seed.mjs` | 测试 `module/ui/panel.js` 的 seedBackend 种子/去重/迁移逻辑 | `node devtools/test-seed.mjs`（在仓库根运行，读 `module/ui/panel.js`） |
| `get-tools.sh` | 下载 APK 构建工具（build-tools 34 + android.jar）到 `build/`，缺失时生成签名密钥 | `bash devtools/get-tools.sh` |
| `build-apk.sh` | 构建 `MihomoControl.apk`（aapt2+javac+d8+zipalign+apksigner）到 `module/bin/` | 先 `get-tools.sh` 再 `bash devtools/build-apk.sh` |

## 说明

- **构建工具缓存**：`get-tools.sh` 下载到 `build/bt`、`build/android.jar`。`build/` 已被 gitignore，本地编译期生成，不入库。
- **APK 构建**：`build-apk.sh` 依赖 `build/` 下工具（见 `get-tools.sh`），输出 `module/bin/MihomoControl.apk`。
- **编译产物约定**：AVD 等本地编译产物统一放 `build/`（gitignore），不再散落在仓库其他位置。
- **外部克隆**（zashboard/mihomo/KernelSU/Meta-Docs）在 `tmp/`，同样不入库。
