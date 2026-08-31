# AGENTS.md

Guidance for AI agents working in this repository. Read this before making changes.
It is written to be self-maintaining: after any change that affects architecture,
lifecycle, paths, or the build pipeline, **update this file in the same commit** so it
never drifts from the code. Do not degrade its quality or truncate it — keep it complete.

---

## 1. What this project is

**SU Clash (module id `suclash`)** is a KernelSU / ReSukiSU / Magisk module that runs the
[`mihomo`](https://github.com/MetaCubeX/mihomo) proxy core in **TUN mode** (not Android
`VpnService`). It gives the user:

- TUN-based routing for all apps with **zero module-side `iptables`/`nftables`** — routing
  and egress are delegated entirely to mihomo's own `auto-route` + `auto-detect-interface`
  (sing-tun ip-rule / fwmark policy routing).
- A config-handling layer that **never rewrites the user's file**.
- A watchdog that auto-restarts a dead/hung core and **circuit-breaks** on repeated crashes.
- A companion APK (`io.github.suclash.control`) providing a Quick-Settings tile, a
  persistent notification, and a WebView-based config UI.
- A [zashboard](https://github.com/Zephyruso/zashboard) Web UI (floating panel injected)
  served by mihomo's `external-ui`.

`main` branch is the current one (commit style `prefix: subject`).

---

## 2. Repository layout (source of truth — paths below are load-bearing)

```
ksuclash/
├── .github/workflows/build-module.yml   # CI: build core + zashboard + APK, package zip
├── devtools/                            # ALL dev & pipeline scripts (see §6)
│   ├── deploy.sh / deploy.ps1           #   push/install to device, control, logs
│   ├── make-module-zip.py               #   zip packer (keeps exec bit, fwd slashes)
│   ├── patch-ui.mjs                     #   zashboard dist → module/ui + inject floating panel
│   ├── test-seed.mjs                    #   unit-test panel.js seed logic
│   ├── get-tools.sh                     #   download APK build tools → build/  (gitignored)
│   ├── build-apk.sh                     #   build MihomoControl.apk → module/bin/
│   └── README.md
├── helper-apk/                          # Companion APK SOURCE ONLY (no build scripts here)
│   ├── AndroidManifest.xml
│   ├── java/io/github/suclash/control/  #   MainActivity, ConfigActivity, KsuBridge,
│   │                                     #   Root, Notif, ProxyTileService, TileState,
│   │                                     #   BootReceiver, ActionReceiver, ConfigProvider
│   └── res/
├── helper-go/                           # Go binary `suclash_helper` (all core logic)
│   ├── main.go                          #   CLI dispatch
│   ├── paths.go                         #   ALL path constants — do not rename (APK/scripts depend)
│   ├── process.go                       #   start/stop/status/restart + process model
│   ├── watchdog.go                      #   watchdog loop, circuit breaker, tun/api probes
│   ├── patch.go                         #   runtime.yaml + panel-config.js generation
│   ├── api.go                           #   Clash REST client (replaces nc hand-written HTTP)
│   ├── ui.go                            #   panel URL, ui self-heal/resync/repatch
│   ├── misc.go                          #   config import, enable/disable, toggle, resume, logs
│   ├── util.go                          #   logging, tile state, pid files, process checks
│   ├── sys_linux.go / sys_stub.go       #   platform syscalls (flock, kill, setsid, freezer)
│   └── go.mod                           #   module github.com/suclash/helper, gopkg.in/yaml.v3
├── module/                              # The installable module (what gets zipped)
│   ├── customize.sh                     #   install/upgrade (arch selection, perms, data dir)
│   ├── service.sh                       #   boot entry (thin glue; delegates to helper)
│   ├── action.sh                        #   KernelSU "Action" button menu (volume keys)
│   ├── uninstall.sh                     #   full cleanup
│   ├── module.prop                      #   id=suclash, name, version
│   ├── config.default.yaml              #   default user config template
│   ├── scripts/clashctl                 #   thin shim → exec helper (kept for caller compat)
│   ├── bin/                             #   build artifacts (gitignored, rebuilt by CI)
│   │   ├── mihomo                       #     core binary (arch-selected at install)
│   │   ├── suclash_helper               #     helper binary (arch-selected)
│   │   └── MihomoControl.apk            #     companion APK
│   ├── ui/                              #   zashboard (gitignored, built by CI)
│   ├── webroot/index.html               #   manager "WebUI" landing page (status + actions)
│   └── webroot-src/panel.js             #   floating-panel source injected into ui/
├── tmp/                                 # gitignored; external clones only (mihomo, zashboard,
│   └── .gitkeep                         #   KernelSU, Meta-Docs). NOT for build output.
├── build/                               # gitignored; local build tool cache & AVD artifacts
├── clash.yaml                           # gitignored; user's private config w/ subscription token
├── suclash-module.zip                   # gitignored; local packaging output
└── .workbuddy/                          # gitignored; agent memory (not project source)
```

**Git-ignore contract** (`.gitignore`): source lives in `devtools/`, `helper-apk/` (no
`get-tools.sh`/`build-apk.sh` there anymore), `helper-go/`, `module/` (sans artifacts).
Everything reproducible or generated — `module/bin/*`, `module/ui/`, `build/`, `build-avd/`,
`tmp/*`, `*.keystore`, `clash.yaml`, `*.zip` — stays **out of the repo**. Never force-add
build artifacts or secrets.

---

## 3. Runtime architecture (as implemented — supersedes any older design notes)

### 3.1 Two data areas
| Path | Role | Lifecycle |
|---|---|---|
| `/data/adb/modules/suclash/` | Module: binaries, scripts, `ui/`(zashboard), APK | Managed on install/upgrade |
| `/data/adb/suclash/` | User data: `config.yaml`, `runtime.yaml`, `ui/`, `logs/`, `state/`, `cache/` | Deleted on uninstall |

Key rule: **user data lives outside the module dir**, so it survives upgrades.

### 3.2 Process model
```
clashctl (sh shim) ──exec──> suclash_helper <cmd>
   start ──spawnWatchdog()──> suclash_helper watchdog   (setsid, detached)
                                   └─spawnCoreChild()──> mihomo -d /data/adb/suclash -f runtime.yaml
                                                          (child of watchdog; setsid)
```
- **Watchdog is the parent of mihomo.** `cmd.Wait` gives immediate death detection (zero
  polling race). If a core is already running but not its child (e.g. `ensure` back-fill),
  it degrades to PID polling.
- `service.sh` starts only the watchdog; the watchdog owns core lifecycle.
- **Race guards:** `state/helper.lock` (flock, mutual exclusion for start/stop/restart vs
  watchdog respawn) and `state/stopping` (a flag file: watchdog refuses to respawn while set).

### 3.3 Watchdog responsibilities (watchdog.go)
Loop interval `wdIntervalSec = 10s`.
- Core death → crash-count bump → respawn (with short backoff). If **3 crashes in a
  `crashWindowSec = 600s` window** → **circuit-break (panic)**: write `state/panic`, set tile
  to `panic`, stop core, disable autostart. User must run `clashctl resume` to recover.
- **tun iface missing** (core alive but `sing-tun` failed) for 2 consecutive cycles → restart.
- **API hang** (process alive but `/version` fails 2 cycles) → forensics
  (`hangdump.log`: `/proc/status`, `wchan`, `cgroup`, then **SIGQUIT** for a Go goroutine
  dump) → SIGKILL → restart. Repeated hangs also trip the breaker.
- Log rotation past `logMaxBytes` (8 MiB, keeps one `.old`).
- The watchdog calls `escapeFreezer(pid)` — moves core out of the `uid_xxx` frozen cgroup so
  Android background-freezing can't black-hole the tunnel (critical; keep it).

### 3.4 Config handling (patch.go) — "minimal intrusion"
- User file `/data/adb/suclash/config.yaml` is **read-only**; it is never modified in place.
- On start/patch the helper generates `runtime.yaml` = user config + **forced overrides**:
  1. `tun.enable: true` (inject default tun block if absent/scalar — `auto-route`,
     `auto-detect-interface`, `strict-route:false`, `dns-hijack: 0.0.0.0:53`).
  2. `dns.enable: true` (inject default dns block — fake-ip `198.18.0.1/16`, etc.).
  3. `external-ui` **always** forced to the data-dir `ui/` path.
  4. `external-controller` defaults to `127.0.0.1:9090` only if absent.
  - Everything else (ports, mode, rules, nodes, secret, DNS details) is preserved verbatim.
- Also writes `data/ui/panel-config.js` (API host/port/secret) for the floating panel.
- **Why data `ui/` not module `ui/`:** mihomo `external-ui` only serves paths inside the
  `-d` (data) directory. `syncUIFromModule()` copies module `ui/` → data `ui/` on first run.
- Config is validated with `mihomo -t` before launch (never start with a broken config).

### 3.5 Why a Go binary instead of shell
The module historically was ~900 lines of shell (busybox `awk` `sub`/`gsub` segfaults on
multi-byte UTF-8 ranges; fragile `nc` hand-written HTTP; `sed` JSON scraping). Everything was
consolidated into the single Go binary `suclash_helper`. **Shell now only holds
KernelSU/Magisk lifecycle glue** (`service.sh`, `customize.sh`, `uninstall.sh`, `action.sh`,
`scripts/clashctl` shim). Keep it that way.

### 3.6 Web UI
- zashboard is served by mihomo `external-ui` at `http://127.0.0.1:9090/ui/` — **same origin**
  as the Clash API, so no CORS/mixed-content issues.
- Module `webroot/index.html` is the manager "WebUI" entry: status card + start/stop/restart,
  and a "open panel" button that `location.replace`s to the panel URL.
- **Floating panel** is injected into zashboard's `index.html` by `patch-ui.mjs` at build time
  (`panel.js` + `panel-config.js`). It does core operations via `window.ksu.exec` root bridge,
  plus API operations (mode switches). In a plain browser it degrades to API-only.
- `KsuBridge` in the APK provides a `window.ksu.exec` with the **same signature** as KernelSU
  manager, so the same panel code runs in both the manager WebView and the app WebView.
- UI self-healing: `cmdRepatchUI` re-injects the scripts and regenerates `panel-config.js`
  after `POST /upgrade/ui` (zashboard self-upgrade wipes the dir) or on start.

### 3.7 Companion APK (`io.github.suclash.control`)
No foreground service, no wake locks. Components:
- `MainActivity` — main console (launcher).
- `ConfigActivity` — config management screen.
- `KsuBridge` — root bridge for the floating panel (`window.ksu.exec`, `version`, `openConfig`).
- `Root` — runs `su -c clashctl …` (user must grant root to the app once in the manager).
- `Notif` — persistent static notification (post on boot; pause/resume/restart actions).
- `ProxyTileService` — Quick-Settings tile (tap=toggle, long-press=open app).
- `TileState` — tile state read from `state/tile` via root.
- `BootReceiver` — posts notification on boot.
- `ActionReceiver` — notification action intents.
- `ConfigProvider` — exposes config via ContentProvider.

---

## 4. Module lifecycle (install / upgrade / boot / uninstall)

### 4.1 `customize.sh` (install & upgrade)
- Arch selection: `arm64` (default), `arm→armv7`, `x86_64/x64→amd64`, `x86→386`.
  **Never silently fall back to arm64** for other archs — abort if the tagged binary is absent.
  Renames `bin/mihomo.<tag>` → `bin/mihomo` and deletes leftover arch variants.
  Same for `suclash_helper.<tag>`.
- Sets exec bits (`set_perm`/`set_perm_recursive`).
- Creates data dirs; copies `ui/` to data `ui/`; copies default config only if absent.
- Sets `state/enabled=1` on first install.
- **APK is NOT `pm install`ed at install time** — the old module is still running until reboot
  (upgrade lands in `modules_update/`), so installing the new app now would desync from the
  live tile/notification. Instead it records `state/apk.md5` (md5 of the new APK); after
  reboot `service.sh` compares and installs/updates if needed.

### 4.2 `service.sh` (boot)
- Waits up to 3 min for `sys.boot_completed`, +5s for netd, then up to 90s for network
  (`ping 223.5.5.5`) so mihomo can fetch subscriptions/rules.
- Fresh `logs/boot.log` per boot; `chmod 755` backstop.
- Starts core if `state/enabled != 0`.
- A second background block (after 20s) idempotently installs/updates the APK: installs if the
  package is missing **or** the md5 differs from `state/apk.md5`; only writes the fingerprint
  on success so it retries next boot.
- Must never block boot.

### 4.3 `uninstall.sh`
- Stops core + watchdog (TERM then KILL fallback), kills pids from `state/*.pid`.
- Deletes `/data/adb/suclash`.
- `pm uninstall --user 0 io.github.suclash.control` with a background retry loop (pm may not be
  ready during early uninstall). **No system residue** — no system props, no mount, no
  persistent iptables/routes.

### 4.4 `action.sh` (KernelSU Action button)
Volume-key menu read via `getevent`: VolUp = force-stop all module procs + best-effort restore
(delete stale TUN ifaces `Meta`/`mihomo`, clear all runtime state), VolDown = restart module
(and clear panic). 20s timeout. This is the manual escape hatch for a wedged module.

---

## 5. CLI contract (`clashctl` / `suclash_helper`)

`scripts/clashctl` is a thin shim that `exec`s the helper, kept so callers (APK
`Root.SCRIPT`, notification buttons, tile, `panel.js` via `ksu.exec`) use the unchanged path
`sh /data/adb/modules/suclash/scripts/clashctl <cmd>`.

Commands:
```
start | stop | restart | status | mode <direct|rule|global>
toggle | reload | resume | enable | disable
patch | panel | reset-ui | repatch-ui | config <path>
log [n] | mlog [n] | version
watchdog        # internal; started by `start`, not meant to be run manually
```

**Output contract — do not break it.** The APK parses `status` by regex
(`state=(\w+)`); tile state values are `on|off|starting|stopping|panic`. `status` prints:
```
state=<tile> pid=<pid> tun=<up|->
api=<version> mode=<mode>     # "api=unreachable" if API down
panel=<url>
[panic=<reason>]
[watchdog=<pid>]
```

---

## 6. Development & build pipeline

All scripts are in `devtools/`. Scripts = source (committed); **build artifacts and tool
caches = `build/` (gitignored)**.

| Task | Command |
|---|---|
| Deploy module to device (dev loop) | `bash devtools/deploy.sh [push\|config\|start\|stop\|status\|log\|all]` (or `deploy.ps1`) |
| Build APK | `bash devtools/get-tools.sh` then `bash devtools/build-apk.sh` |
| Package UI + inject floating panel | `node devtools/patch-ui.mjs <zashboard-dist> <module-root>` |
| Zip the module | `python3 devtools/make-module-zip.py <module-root> <out.zip>` |
| Test panel seed logic | `node devtools/test-seed.mjs` |

- `get-tools.sh` downloads build-tools 34 + android.jar into `build/`, and generates a signing
  keystore if missing (keystore is gitignored; never commit it).
- `build-apk.sh` runs aapt2 → javac → d8 → zipalign → apksigner and emits
  `module/bin/MihomoControl.apk`.
- `make-module-zip.py` uses forward slashes and explicitly preserves the exec bit (some
  installers drop zip modes), and excludes `webroot-src/`.

### 6.1 CI (`build-module.yml`)
Triggers: **manual dispatch only** (`workflow_dispatch`) + **weekly cron (Mon 03:00 UTC)**.
Push-based triggers were removed so a plain push to `main` does not auto-build — builds are
always explicit (manual) or scheduled. The cron is the "self-update" that tracks latest
upstream.
Steps: resolve latest mihomo release → download **android-arm64-v8** asset (verified as
aarch64 ELF) → cross-compile **Go helper** (`CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build`,
pure-Go, no NDK) → build latest zashboard `main` with `FONT=none` → `patch-ui.mjs` → build APK →
stamp `module.prop` (version `v1.0.0-<date>-mihomo<ver>`, versionCode = unix-time-derived) →
`make-module-zip.py` → upload artifact → release on tag (`v*`).
**`module/bin` must end up with three binaries** for the zip to work: `mihomo`, `suclash_helper`
and `MihomoControl.apk` — a missing helper makes the module inert, so the helper build step is
load-bearing.

---

## 7. Gotchas & hard-won lessons (read before editing)

1. **Paths in `paths.go` are load-bearing.** The APK and shell scripts reference them by
   string. Do not rename dirs/files without auditing every caller. (e.g. `modDir`,
   `dataDir`, `binDir`, `scrDir`, `modUIDir`, `stateDir`, `logDir`, `dataUIDir`, `userCfg`,
   `runtimeCfg`, `coreLog`, `moduleLog`, pid/flag file names.)
2. **Never modify the user's `config.yaml`.** Only `runtime.yaml` is our generated artifact.
   It's rebuilt on every start — order/format not guaranteed, only key/values.
3. **`external-ui` must be inside the `-d` data dir** (mihomo restriction). Always operate on
   `data/ui/`, and re-sync from `module/ui/` if missing.
4. **APK lifecycle is deferred to reboot** — don't `pm install` in `customize.sh`. Track the
   fingerprint and let `service.sh` install on next boot.
5. **Freezer cgroup is a tunnel black-hole.** Any core process launched via manager `su`
   inherits the `uid_xxx` frozen group; if the system freezes it, the whole TUN goes dark.
   `escapeFreezer` is mandatory on every spawn.
6. **Do not add module-side `iptables`/`nftables` or persistent routes.** Failure-safety is
   "core dies → tun vanishes → kernel reclaims routes → device returns to direct".
7. **Process management is Go's job, not shell.** `clashctl` is a shim. Extend the helper in
   `helper-go`, keep shell as thin glue only. Guard concurrent ops with `helper.lock` and
   `stopping` to prevent stop-vs-respawn races.
8. **BuildTime/ldflags pitfall (for NDK/local cross-builds):** when injecting a build time via
   `-ldflags`, a `date` string containing a space will split into multiple args and make the
   linker print usage. Use the no-space format `date -u +%Y-%m-%dT%H:%M:%SZ`.
9. **Android core needs cgo (NDK).** mihomo's net/tailscale/gvisor deps require external C
   linking for `android` targets; a pure-Go build fails with `requires external (cgo) linking`.
   Cross-compile with `CC=<triple>-clang`, `CGO_ENABLED=1`, `GOOS=android`. (amalgamated into
   the `avd-magisk-module-test` skill — reuse it.)
10. **`mihomo` android/amd64 asset name** has no `GOAMD64` suffix (`mihomo-android-amd64-<ver>.gz`),
    unlike linux/darwin/windows (v1/v2/v3). If you touch core-version/self-upgrade code, keep
    this in mind (see upstream PR history if you change `coreBaseName`).
11. **Keep `status` output format stable.** The APK regex-parses it. Changing the shape breaks
    the tile/notification.
12. **Config validation before start** (`mihomo -t`): a syntax error must be caught pre-launch,
    never run a broken core.
13. **Never `pm uninstall` blocking** in `uninstall.sh` early boot — pm may be unready; use a
    bounded background retry.

---

## 8. Testing & verification loop

- **Unit tests:** `node devtools/test-seed.mjs` exercises `module/ui/panel.js` seed/dedupe/
  migration logic (run from repo root).
- **Device/AVD loop:** build a test variant (x86_64), install into an AVD running Magisk,
  reboot, and verify: `clashctl status` shows `state=on`, `/version` returns a version, TUN is
  up, and core self-upgrade works. Full workflow (NDK cross-compile → package → install →
  verify) is captured in the `avd-magisk-module-test` skill — follow it rather than improvising.
- After code changes, run the relevant syntax checks: `bash -n` for sh, `go build`/`go vet` for
  helper, `node --check` for mjs, and py_compile for python.

---

## 9. Maintenance contract for AGENTS.md

- **Update this file in the same commit as any change** that alters: directory layout or
  load-bearing paths, the process model, the CLI/output contract, lifecycle (customize/service/
  uninstall) semantics, or the build/CI pipeline.
- Keep it accurate over exhaustive — if something here disagrees with the code, the code and a
  small fix to this file win together.
- Do not delete, truncate, or downgrade sections to save space. If the project grows, extend,
  don't compress.
