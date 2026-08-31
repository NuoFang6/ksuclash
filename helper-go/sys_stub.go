//go:build !linux

package main

import (
	"errors"
	"os"
	"os/exec"
	"syscall"
)

// 非 linux 构建目标的存根：仅保证 Windows 开发机上 go vet / IDE 不报错。
// 实际产物仅交叉编译 linux/arm64 与 linux/amd64。

type fakeSignal struct{}

func (fakeSignal) String() string { return "stub" }
func (fakeSignal) Signal()        {}

var (
	sigTERM = syscall.SIGTERM
	sigINT  = syscall.SIGINT
)

func syscallKill(pid int, sig any) error { return errors.New("non-linux build") }

func newDetachAttr() any { return nil }

func flockTry(f *os.File) error { return errors.New("non-linux build") }

func newCmdSysProc(c *exec.Cmd) {}
