package main

import (
	"fmt"
	"os"
	"os/exec"
	"time"
)

// runCmd 执行外部命令并返回标准输出（getprop 等系统探测用）。
func runCmd(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// appendModuleLog 追加模块日志。
func appendModuleLog(format string, a ...any) {
	f, err := os.OpenFile(moduleLog, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "[%s] %s\n", time.Now().Format("01-02 15:04:05"), fmt.Sprintf(format, a...))
}

// setTile 写磁贴/通知可读状态文件: on|off|starting|stopping|panic
func setTile(s string) {
	_ = os.WriteFile(tileFl, []byte(s), 0o644)
}

// rotateLog 超限轮转（保留一份 .old）。
func rotateLog() {
	st, err := os.Stat(coreLog)
	if err != nil || st.Size() <= logMaxBytes {
		return
	}
	_ = os.Rename(coreLog, coreLog+".old")
}

// ensureDirs 创建运行目录。
func ensureDirs() {
	for _, d := range []string{stateDir, logDir, dataDir + "/cache", dataUIDir} {
		_ = os.MkdirAll(d, 0o755)
	}
}

// writePIDFile / readPIDFile
func writePIDFile(path string, pid int) {
	_ = os.WriteFile(path, []byte(fmt.Sprintf("%d", pid)), 0o644)
}

func readPIDFile(path string) (int, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	var pid int
	if _, err := fmt.Sscanf(string(b), "%d", &pid); err != nil || pid <= 0 {
		return 0, false
	}
	return pid, true
}

// procAlive 检查进程是否存在。
func procAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	return syscallKill(pid, 0) == nil
}

// procIsMihomo 校验 /proc/<pid>/cmdline 含 mihomo，防 PID 复用误判。
func procIsMihomo(pid int) bool {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	if err != nil {
		return false
	}
	return len(b) > 0 && (containsBytes(b, []byte("mihomo")) || containsBytes(b, []byte(runtimeCfg)))
}

// procIsWatchdog 校验 PID 对应的是本模块的 watchdog，防止 PID 复用误杀其他进程。
func procIsWatchdog(pid int) bool {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	if err != nil {
		return false
	}
	return containsBytes(b, []byte(helperBin)) && containsBytes(b, []byte("watchdog"))
}

func containsBytes(hay, needle []byte) bool {
	if len(needle) == 0 || len(hay) < len(needle) {
		return false
	}
	for i := 0; i+len(needle) <= len(hay); i++ {
		match := true
		for j := range needle {
			if hay[i+j] != needle[j] {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
