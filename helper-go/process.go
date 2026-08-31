package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// 进程管理：mihomo 的启动/停止/探测 + 看门狗进程管理。
//
// 进程模型（watchdog 为 mihomo 父进程）：
//   mihomo     由 watchdog spawn 的子进程（cmd.Wait 即时感知死亡，零轮询竞态）
//   watchdog   `suclash_helper watchdog` 独立进程（setsid 脱离 start 调用方）
//              核心已运行但非其子进程时（ensure 补起场景）降级为 pid 轮询
//
// 竞态防护：
//   state/helper.lock 文件锁：start/stop/restart 与看门狗拉起互斥
//   state/stopping     标记文件：看门狗拉起守卫（stop 期间不重启）
//
// 自愈能力（沿用 shell 版语义）：
//   崩溃熔断（600s 窗口 3 次 → panic 熔断）、
//   API 挂死取证（SIGQUIT goroutine dump → hangdump.log）后强杀重启。

// lockState 获取状态锁（非阻塞）。返回 nil 表示成功。
func lockState() (*os.File, error) {
	f, err := os.OpenFile(stateDir+"/helper.lock", os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := flockTry(f); err != nil {
		f.Close()
		return nil, fmt.Errorf("另一个 clash 管理操作正在进行中")
	}
	return f, nil
}

func unlockState(f *os.File) {
	if f != nil {
		_ = f.Close() // 关闭即释放 flock
	}
}

// corePID 返回核心 pid（含 /proc 校验防 PID 复用）；-1 表示未运行。
func corePID() int {
	pid, ok := readPIDFile(pidFile)
	if !ok {
		return -1
	}
	if !procAlive(pid) || !procIsMihomo(pid) {
		return -1
	}
	return pid
}

// watchdogPID 返回看门狗 pid；-1 表示未运行。
func watchdogPID() int {
	pid, ok := readPIDFile(wdPidFile)
	if !ok {
		return -1
	}
	if !procAlive(pid) {
		return -1
	}
	return pid
}

// waitProcExit 轮询等待进程退出（上限 sec 秒）。
func waitProcExit(pid, sec int) bool {
	deadline := time.Now().Add(time.Duration(sec) * time.Second)
	for time.Now().Before(deadline) {
		if !procAlive(pid) {
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}
	return !procAlive(pid)
}

// termProc SIGTERM → 等 termWaitSec → SIGKILL → 确认退出。
func termProc(pid int) {
	if pid <= 0 || !procAlive(pid) {
		return
	}
	_ = syscallKill(pid, 15)
	if !waitProcExit(pid, termWaitSec) {
		_ = syscallKill(pid, 9)
		waitProcExit(pid, 3)
	}
}

// stopWatchdogProc 停止看门狗（TERM 后它会带走自己名下的 mihomo 子进程）。
func stopWatchdogProc() {
	pid := watchdogPID()
	if pid < 0 {
		return
	}
	_ = syscallKill(pid, 15)
	if !waitProcExit(pid, termWaitSec) {
		_ = syscallKill(pid, 9)
		waitProcExit(pid, 3)
	}
	_ = os.Remove(wdPidFile)
}

// spawnWatchdog 拉起看门狗进程（若已在运行则复用）。
func spawnWatchdog() (int, error) {
	if pid := watchdogPID(); pid > 0 {
		return pid, nil
	}
	pid, err := spawnDetached(helperBin, "watchdog")
	if err != nil {
		return 0, fmt.Errorf("看门狗启动失败: %w", err)
	}
	writePIDFile(wdPidFile, pid)
	appendModuleLog("watchdog started (pid %d)", pid)
	return pid, nil
}

// waitForCore 就绪等待：pidfile 出现且 API 可达；返回核心 pid。
func waitForCore() (int, bool) {
	for i := 0; i < startWaitSec; i++ {
		time.Sleep(1 * time.Second)
		if pid := corePID(); pid > 0 && apiOK() {
			return pid, true
		}
	}
	if pid := corePID(); pid > 0 {
		return pid, false
	}
	return -1, false
}

// ---- 子命令 ----

func cmdStart(args []string) error {
	ensureDirs()
	lock, err := lockState()
	if err != nil {
		return err
	}
	defer unlockState(lock)

	// 熔断检查：panic 态拒绝启动，需 resume 显式恢复
	if fileExists(panicFl) {
		fmt.Printf("panic: 看门狗熔断中（%s）\n", readFileTrim(panicFl))
		fmt.Println("如确认已修复请执行: clashctl resume")
		return fmt.Errorf("panic 熔断中")
	}

	// 权限兜底：zip/安装器可能丢失可执行位
	for _, p := range []string{mihomoBin, helperBin} {
		if st, err := os.Stat(p); err == nil && st.Mode()&0o111 == 0 {
			_ = os.Chmod(p, 0o755)
		}
	}

	// 同步面板到数据目录（external-ui 要求 home 子路径）
	if _, err := os.Stat(dataUIDir + "/index.html"); err != nil {
		syncUIFromModule()
	}

	if pid := corePID(); pid > 0 {
		if _, err := spawnWatchdog(); err != nil {
			return err
		}
		fmt.Printf("already running (pid %d)\n", pid)
		return nil
	}

	_ = os.Remove(stoppingFl)

	if _, err := ensureDefaultConfig(); err != nil {
		return fmt.Errorf("默认配置放置失败: %w", err)
	}
	if !fileExists(enabledFl) {
		_ = os.WriteFile(enabledFl, []byte("1"), 0o644)
	}
	if err := doPatch(); err != nil {
		return fmt.Errorf("runtime 配置生成失败: %w", err)
	}
	if err := validateRuntime(); err != nil {
		return err
	}

	// 清理陈旧运行状态（断电/强杀残留）
	_ = os.Remove(probeFailFl)

	setTile("starting")
	// 看门狗负责 spawn mihomo（父子模型：Wait 即时感知死亡）
	if _, err := spawnWatchdog(); err != nil {
		setTile("panic")
		return err
	}

	pid, ready := waitForCore()
	if pid < 0 {
		setTile("panic")
		appendModuleLog("core failed to start (watchdog pid %d)", watchdogPID())
		return fmt.Errorf("核心启动失败，详见 %s 与 %s", coreLog, moduleLog)
	}
	setTile("on")
	appendModuleLog("core started (pid %d)", pid)
	_ = cmdRepatchUI(nil) // 幂等自愈注入（原 clashctl start 成功后的 repatch 语义）
	if !ready {
		fmt.Printf("started (pid %d) but api not ready in %ds, watchdog will monitor\n", pid, startWaitSec)
	} else {
		fmt.Printf("running (pid %d)\n", pid)
	}
	return nil
}

func cmdStop(args []string) error {
	lock, err := lockState()
	if err != nil {
		return err
	}
	defer unlockState(lock)

	setTile("stopping")
	_ = os.WriteFile(stoppingFl, []byte("1"), 0o644) // 看门狗拉起守卫

	// 先停看门狗（它会带走自己名下的 mihomo 子进程，消除拉起窗口）
	stopWatchdogProc()

	// 兜底：看门狗已死/轮询模式下由这里停核心
	if pid := corePID(); pid > 0 {
		termProc(pid)
		appendModuleLog("core stopped (pid %d)", pid)
	}
	_ = os.Remove(pidFile)
	_ = os.Remove(stoppingFl)
	setTile("off")
	fmt.Println("stopped")
	return nil
}

func cmdRestart(args []string) error {
	_ = cmdStop(nil)
	return cmdStart(nil)
}

func cmdStatus(args []string) error {
	pid := corePID()
	tile := "off"
	if s := readFileTrim(tileFl); s != "" {
		tile = s
	}
	if fileExists(panicFl) {
		tile = "panic"
	}
	ver, mode := "", ""
	if code, body, err := apiRequest("GET", "/version", ""); err == nil && code == 200 {
		ver = extractJSONString(body, "version")
		if code2, body2, err2 := apiRequest("GET", "/configs", ""); err2 == nil && code2 == 200 {
			mode = extractJSONString(body2, "mode")
		}
	}
	// 输出格式与原 clashctl 兼容（APK 以 state=(\w+) 解析）
	fmt.Printf("state=%s pid=%d\n", tile, pid)
	if ver == "" {
		fmt.Println("api=unreachable")
	} else if mode != "" {
		fmt.Printf("api=%s mode=%s\n", ver, mode)
	} else {
		fmt.Printf("api=%s\n", ver)
	}
	fmt.Printf("panel=%s\n", panelURL())
	if fileExists(panicFl) {
		fmt.Printf("panic=%s\n", readFileTrim(panicFl))
	}
	if wd := watchdogPID(); wd > 0 {
		fmt.Printf("watchdog=%d\n", wd)
	}
	return nil
}

// readFileTrim 读文件并去首尾空白；失败返回空串。
func readFileTrim(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// validateRuntime 用 mihomo -t 校验 runtime.yaml（原 clashctl validate 语义）。
func validateRuntime() error {
	cmd := exec.Command(mihomoBin, "-d", dataDir, "-t", "-f", runtimeCfg)
	newCmdSysProc(cmd)
	out, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}
	tail := lastNLines(string(out), 5)
	appendModuleLog("config test FAILED: %s", lastNLines(string(out), 1))
	if f, err := os.OpenFile(coreLog, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err == nil {
		fmt.Fprintln(f, tail)
		_ = f.Close()
	}
	return fmt.Errorf("配置校验失败（mihomo -t）: %s", tail)
}

// lastNLines 返回文本尾部 n 行。
func lastNLines(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

// escapeFreezer 根因防御（保留 shell 版语义）：经管理器 su 启动时进程会继承
// uid_xxx 冻结组，系统后台冻结该组时隧道整体黑洞。移入 system 组（不受冻结）。
func escapeFreezer(pid int) {
	targets := []string{
		"/sys/fs/cgroup/system/cgroup.procs", // cgroup v2
		"/dev/cpuset/top-app/tasks",          // v1 兜底
		"/dev/cpuset/tasks",
	}
	for _, t := range targets {
		if f, err := os.OpenFile(t, os.O_WRONLY, 0o644); err == nil {
			_, _ = fmt.Fprintf(f, "%d", pid)
			_ = f.Close()
		}
	}
}

// extractJSONString 从 JSON 文本提取字符串字段值。
func extractJSONString(body, key string) string {
	needle := "\"" + key + "\":\""
	i := indexOf(body, needle)
	if i < 0 {
		return ""
	}
	rest := body[i+len(needle):]
	j := indexOf(rest, "\"")
	if j < 0 {
		return ""
	}
	return rest[:j]
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func cmdMode(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("用法: mode <direct|rule|global>")
	}
	m := args[0]
	switch m {
	case "direct", "rule", "global":
	default:
		return fmt.Errorf("无效模式: %s", m)
	}
	code, _, err := apiRequest("PATCH", "/configs", `{"mode":"`+m+`"}`)
	if err != nil {
		return fmt.Errorf("API 不可达: %w", err)
	}
	if code != 204 && code != 200 {
		return fmt.Errorf("切换失败: HTTP %d", code)
	}
	fmt.Println("mode: " + m)
	return nil
}

func cmdReload(args []string) error {
	code, _, err := apiRequest("PUT", "/configs?force=true", `{"path":"`+runtimeCfg+`"}`)
	if err != nil {
		return fmt.Errorf("API 不可达: %w", err)
	}
	if code != 204 && code != 200 {
		return fmt.Errorf("重载失败: HTTP %d", code)
	}
	fmt.Println("reloaded")
	return nil
}
