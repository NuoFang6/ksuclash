package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"time"
)

// 看门狗（替代 watchdog.sh，语义对齐并增强）：
//   - 父进程模式：spawn mihomo 为子进程，cmd.Wait 即时感知死亡（零轮询竞态）
//   - 轮询模式：核心已运行但非自己子进程（ensure 补起场景），周期 pid 探测
//   - 崩溃熔断：600s 窗口内 maxCrash 次 → panic 熔断（写 panic 文件、tile=panic、退出）
//   - API 挂死：连续 2 个周期无响应 → 取证(SIGQUIT goroutine dump) → 强杀重启

type watchdogT struct {
	child     *exec.Cmd
	childExit chan error // nil 表示轮询模式（非子进程）
	done      bool
	probeFail int // API 探测连续失败计数（挂死熔断前）
}

// spawnDetached 启动脱离会话的子进程并返回 pid（不等待）。
func spawnDetached(path string, args ...string) (int, error) {
	cmd := exec.Command(path, args...)
	newCmdSysProc(cmd)
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	go func() { _ = cmd.Wait() }() // 回收，避免僵尸
	return pid, nil
}

// spawnCoreChild 以本进程为父启动 mihomo，记录退出 channel。
func (w *watchdogT) spawnCoreChild() error {
	rotateLog()
	logF, err := coreLogWriter()
	if err != nil {
		return err
	}
	defer logF.Close()
	cmd := exec.Command(mihomoBin, "-d", dataDir, "-f", runtimeCfg)
	cmd.Stdout = logF
	cmd.Stderr = logF
	newCmdSysProc(cmd) // setsid：核心独立会话，watchdog 重启不影响
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("mihomo 启动失败: %w", err)
	}
	w.child = cmd
	w.childExit = make(chan error, 1)
	writePIDFile(pidFile, cmd.Process.Pid)
	escapeFreezer(cmd.Process.Pid) // 脱离 freezer cgroup，防后台冻结隧道黑洞
	child := cmd
	go func() { w.childExit <- child.Wait() }()
	return nil
}

// coreLogWriter 返回 mihomo stdout/stderr 的目标 writer。
//   - 默认不保存日志：写入 /dev/null（丢弃），零落盘、零 I/O。
//   - 开关开启（state/save_log 存在）：重定向到 coreLog。用不带 O_SYNC 的
//     普通 O_APPEND 打开，写入先进内核 page cache 由内核批量落盘（不强制
//     fsync），既保证可回看，又避免高频同步写拖慢磁盘。
func coreLogWriter() (io.WriteCloser, error) {
	if fileExists(saveLogFl) {
		return os.OpenFile(coreLog, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	}
	f, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		return nil, err
	}
	return f, nil
}

// crashBump 崩溃计数（窗口语义与 shell 版一致），返回窗口内累计次数。
func crashBump() int {
	now := time.Now().Unix()
	n, ts := 0, int64(0)
	if b, err := os.ReadFile(crashFl); err == nil {
		fmt.Sscanf(string(b), "%d %d", &n, &ts)
	}
	if ts == 0 || now-ts > crashWindowSec {
		n, ts = 0, now
	}
	n++
	_ = os.WriteFile(crashFl, []byte(fmt.Sprintf("%d %d", n, ts)), 0o644)
	return n
}

// fuse 熔断：写 panic 文件、tile=panic、记录日志。
func fuse(reason string) {
	_ = os.WriteFile(panicFl, []byte(reason+" "+time.Now().Format("01-02 15:04")), 0o644)
	setTile("panic")
	appendModuleLog("PANIC: %s, auto-disabled", reason)
	_ = os.Remove(pidFile)
}

// hangDump 挂死取证：/proc 信息 + SIGQUIT 触发 goroutine dump。
func hangDump(pid int) {
	f, err := os.OpenFile(hangdumpFl, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "===== HANG DETECTED %s =====\n", time.Now().Format("2006-01-02 15:04:05"))
	if b, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid)); err == nil {
		for _, line := range strings.Split(string(b), "\n") {
			for _, k := range []string{"Name:", "State:", "Frozen:", "Threads:"} {
				if strings.HasPrefix(line, k) {
					fmt.Fprintf(f, "%s\n", line)
				}
			}
		}
	}
	if b, err := os.ReadFile(fmt.Sprintf("/proc/%d/wchan", pid)); err == nil {
		fmt.Fprintf(f, "--- wchan ---\n%s\n", string(b))
	}
	if b, err := os.ReadFile(fmt.Sprintf("/proc/%d/cgroup", pid)); err == nil {
		lines := strings.SplitN(string(b), "\n", 2)
		fmt.Fprintf(f, "--- cgroup ---\n%s\n", lines[0])
	}
	// SIGQUIT 让 Go 运行时把 goroutine 栈写进 coreLog
	_ = syscallKill(pid, 3)
	appendModuleLog("HANG detected: SIGQUIT for goroutine dump, then kill")
}

// restartCore 看门狗内部重启核心（锁 + stopping 双重检查防竞态）。
func (w *watchdogT) restartCore() bool {
	lock, err := lockState()
	if err != nil {
		appendModuleLog("restart aborted: %v", err)
		return false
	}
	defer unlockState(lock)
	if fileExists(stoppingFl) {
		return false
	}
	setTile("starting")
	_ = os.Remove(pidFile)
	if err := doPatch(); err != nil {
		appendModuleLog("repatch on restart failed: %v", err)
	}
	if err := validateRuntime(); err != nil {
		appendModuleLog("restart aborted, config invalid: %v", err)
		setTile("panic")
		return false
	}
	if err := w.spawnCoreChild(); err != nil {
		appendModuleLog("core respawn failed: %v", err)
		return false
	}
	// 等待就绪（不阻塞主循环太久：上限内轮询）
	for i := 0; i < startWaitSec; i++ {
		time.Sleep(1 * time.Second)
		if apiOK() {
			break
		}
	}
	appendModuleLog("core restarted (pid %d)", corePID())
	setTile("on")
	return true
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// shutdown 收到 TERM：停止子进程并清理。
func (w *watchdogT) shutdown() {
	if w.child != nil && w.child.Process != nil {
		termProc(w.child.Process.Pid)
	}
	_ = os.Remove(pidFile)
	w.cleanup()
}

func (w *watchdogT) cleanup() {
	if pid, ok := readPIDFile(wdPidFile); ok && pid == os.Getpid() {
		_ = os.Remove(wdPidFile)
	}
	w.done = true
}

// handleCoreDeath 核心死亡后的处理；返回是否继续循环。
func (w *watchdogT) handleCoreDeath() bool {
	if fileExists(stoppingFl) {
		// 外部 stop 流程进行中，watchdog 退出由 TERM 兜底
		return true
	}
	n := crashBump()
	appendModuleLog("core died (window count=%d)", n)
	if n >= maxCrash {
		fuse(fmt.Sprintf("窗口内崩溃%d次", n))
		return false
	}
	time.Sleep(2 * time.Second)
	if fileExists(stoppingFl) {
		return true
	}
	w.restartCore()
	return true
}

func cmdWatchdog(args []string) error {
	ensureDirs()
	writePIDFile(wdPidFile, os.Getpid())
	// 看门狗自身也要脱离 app 冻结组：escapeFreezer 之前在 spawnCoreChild
	// 只对 mihomo 调用，watchdog 的 cgroup 依赖"继承自启动父进程"（service.sh
	// root 上下文），属恰好同组而非主动保证。若未来 watchdog 从被冻结 app 的
	// su 上下文拉起，会继承 app 冻结组而 mihomo 却在 system 组 → 出现"watchdog
	// 冻结、mihomo 未冻结"的分离，自愈机制整体失效（隧道中断且无人拉起）。
	// 主动把自身也移入 system 组，从根上消除该分离窗口。
	escapeFreezer(os.Getpid())
	// 启动日志由父进程 spawnWatchdog 统一打一次（spawnDetached 之后），
	// 避免每次启动出现两条相同的 "watchdog started" 冗余记录。

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, sigTERM, sigINT)

	w := &watchdogT{}
	if corePID() > 0 {
		// 核心已在运行（ensure 补起场景）：降级轮询模式
		w.childExit = nil
	} else {
		if err := w.spawnCoreChild(); err != nil {
			appendModuleLog("watchdog initial spawn failed: %v", err)
			w.cleanup()
			return err
		}
	}

	ticker := time.NewTicker(time.Duration(wdIntervalSec) * time.Second)
	defer ticker.Stop()

	for !w.done {
		select {
		case <-sigCh:
			w.shutdown()
			return nil
		case <-w.childExit:
			w.childExit = nil // 死亡已感知（事件驱动，无需周期探测）
			if !w.handleCoreDeath() {
				w.cleanup()
				return nil
			}
		case <-ticker.C:
			if w.childExit != nil {
				// 父进程模式：核心死亡已由 childExit channel 事件驱动感知，
				// 这里无需再做周期 pid 存活探测（消除冗余读）。
				// 本 tick 仅做"进程活着但异常"的活性检查（liveness probe）。
				pid := corePID()
				if pid < 0 {
					// childExit 未及时送达的兜底（极端竞态），走一次死亡处理
					if !w.handleCoreDeath() {
						w.cleanup()
						return nil
					}
					continue
				}
				w.healthCheck(pid)
				continue
			}

			// 轮询模式（mihomo 非本进程子进程，ensure 补起场景）：
			// 无 childExit 事件可用，只能靠周期 pid 探测感知死亡。
			if fileExists(stoppingFl) && corePID() < 0 {
				// 用户已停止（pidfile 消失）→ 退出兜底
				appendModuleLog("watchdog exit (no pidfile)")
				w.cleanup()
				return nil
			}
			pid := corePID()
			if pid < 0 {
				if !w.handleCoreDeath() {
					w.cleanup()
					return nil
				}
				continue
			}
			w.healthCheck(pid)
		}
	}
	return nil
}

// healthCheck 父进程/轮询模式共用的活性检查（不做冗余扫描）。
//   - 日志轮转：不做周期轮询。savelog 默认 off 时日志写 /dev/null、mihomo.log
//     不增长，轮转无意义；需要时在 spawnCoreChild（spawn 核心）时事件驱动检查一次。
//   - API 探测：每次 tick（liveness 本质，无法事件驱动）
func (w *watchdogT) healthCheck(pid int) {
	// API 健康探测：检测"进程活着但挂死"（流量黑洞态）——本质是 liveness
	// probe，无内核事件可听（进程有 pid 却不应答），只能主动探测。
	if code, _, err := apiRequest("GET", "/version", ""); err == nil && code > 0 {
		w.probeFail = 0
		return
	}
	w.probeFail++
	appendModuleLog("api probe FAILED (%d)", w.probeFail)
	if w.probeFail < 2 {
		return
	}

	// 挂死确认：取证 → SIGQUIT 抓栈 → 强杀 → 重启
	hangDump(pid)
	time.Sleep(3 * time.Second)
	_ = syscallKill(pid, 9)
	waitProcExit(pid, 3)
	_ = os.Remove(pidFile)
	_ = os.Remove(probeFailFl)
	w.probeFail = 0
	n := crashBump()
	appendModuleLog("hang auto-recovery (count=%d)", n)
	if n >= maxCrash {
		fuse(fmt.Sprintf("反复挂死%d次", n))
		w.cleanup()
		return
	}
	if !w.restartCore() {
		// 核心未能拉起（多为 spawn 失败，validateRuntime 失败已在 restartCore 内
		// setTile("panic")）。若 tile 仍停在 "starting"，收敛为 "off"，避免状态
		// 长期失准；下一 tick 会经 handleCoreDeath 重试并最终熔断。
		if readFileTrim(tileFl) == "starting" {
			setTile("off")
		}
	}
}
