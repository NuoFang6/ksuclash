package main

import (
	"fmt"
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
//   - tun 网卡丢失：连续 2 个周期 → 重启核心
//   - API 挂死：连续 2 个周期无响应 → 取证(SIGQUIT goroutine dump) → 强杀重启

type watchdogT struct {
	child     *exec.Cmd
	childExit chan error // nil 表示轮询模式（非子进程）
	done      bool
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
	logF, err := os.OpenFile(coreLog, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
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

// tunIfaceOK 检查 tun 网卡（Meta/mihomo）是否存在。
func tunIfaceOK() bool {
	ents, err := os.ReadDir("/sys/class/net")
	if err != nil {
		return true // 无法判断时不视为异常
	}
	for _, e := range ents {
		name := strings.ToLower(e.Name())
		if name == "meta" || name == "mihomo" {
			return true
		}
	}
	return false
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
	appendModuleLog("watchdog started (pid %d)", os.Getpid())

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
	probeFail, tunMiss := 0, 0

	for !w.done {
		select {
		case <-sigCh:
			w.shutdown()
			return nil
		case <-w.childExit:
			w.childExit = nil // 死亡已感知
			if !w.handleCoreDeath() {
				w.cleanup()
				return nil
			}
		case <-ticker.C:
			if fileExists(stoppingFl) && corePID() < 0 {
				// 用户已停止（pidfile 消失）→ 退出兜底
				appendModuleLog("watchdog exit (no pidfile)")
				w.cleanup()
				return nil
			}
			pid := corePID()
			if pid < 0 {
				// 轮询模式死亡感知 / 父进程模式下 select 未及时送达
				if w.childExit != nil {
					select {
					case <-w.childExit:
						w.childExit = nil
					default:
					}
				}
				if w.childExit == nil {
					if !w.handleCoreDeath() {
						w.cleanup()
						return nil
					}
				}
				continue
			}
			rotateLog()

			// tun 网卡丢失检测（核心活着但 sing-tun 异常）
			if !tunIfaceOK() {
				tunMiss++
				appendModuleLog("tun iface missing (%d)", tunMiss)
				if tunMiss >= 2 {
					tunMiss = 0
					_ = os.Remove(tunMissFl)
					appendModuleLog("restarting core due to missing tun")
					termProc(pid)
					time.Sleep(2 * time.Second)
					w.restartCore()
				}
				continue
			}
			tunMiss = 0
			_ = os.Remove(tunMissFl)

			// API 健康探测：检测"进程活着但挂死"（流量黑洞态）
			if code, _, err := apiRequest("GET", "/version", ""); err == nil && code > 0 {
				probeFail = 0
				continue
			}
			probeFail++
			appendModuleLog("api probe FAILED (%d)", probeFail)
			if probeFail < 2 {
				continue
			}

			// 挂死确认：取证 → SIGQUIT 抓栈 → 强杀 → 重启
			hangDump(pid)
			time.Sleep(3 * time.Second)
			_ = syscallKill(pid, 9)
			waitProcExit(pid, 3)
			_ = os.Remove(pidFile)
			_ = os.Remove(probeFailFl)
			probeFail = 0
			n := crashBump()
			appendModuleLog("hang auto-recovery (count=%d)", n)
			if n >= maxCrash {
				fuse(fmt.Sprintf("反复挂死%d次", n))
				w.cleanup()
				return nil
			}
			w.restartCore()
		}
	}
	return nil
}
