//go:build linux

package main

import (
	"os"
	"os/exec"
	"syscall"
)

// syscallKill 向进程发送信号。
func syscallKill(pid int, sig syscall.Signal) error {
	return syscall.Kill(pid, sig)
}

var (
	sigTERM = syscall.SIGTERM
	sigINT  = syscall.SIGINT
)

// newDetachAttr 进程脱离会话（setsid），不受调用方退出影响。
func newDetachAttr() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{Setsid: true}
}

// flock 独占非阻塞文件锁。
func flockTry(f *os.File) error {
	return syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
}

// newCmdSysProc 为 exec.Cmd 设置脱离属性。
func newCmdSysProc(c *exec.Cmd) {
	c.SysProcAttr = newDetachAttr()
}
