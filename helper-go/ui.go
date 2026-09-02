package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"strings"
)

// UI 相关：面板地址、从模块安装目录恢复面板。

// syncUIFromModule 将模块内置 zashboard 同步到数据目录（external-ui 要求 home 子路径）。
func syncUIFromModule() {
	_ = os.RemoveAll(dataUIDir)
	if err := os.CopyFS(dataUIDir, os.DirFS(modUIDir)); err != nil {
		appendModuleLog("ui sync from module failed: %v", err)
		return
	}
}

// panelURL 生成 zashboard 面板地址（按 runtime external-controller 推导）。
func panelURL() string {
	cfg, err := loadYAML(runtimeCfg)
	if err == nil {
		if ec, ok := cfg["external-controller"].(string); ok && ec != "" {
			if h, p, ok2 := splitHostPort(ec); ok2 {
				return "http://" + net.JoinHostPort(h, p) + "/ui/"
			}
		}
	}
	return "http://127.0.0.1:9090/ui/"
}

func cmdPanel(args []string) error {
	fmt.Println(panelURL())
	return nil
}

// cmdResetUI 从模块安装目录恢复被破坏的面板（目录损坏/误删时使用）。
// 注入由 mihomo 服务端完成（mihomo-patches/0005），无需文件级自愈。
func cmdResetUI(args []string) error {
	syncUIFromModule()
	if err := doPatch(); err != nil {
		return fmt.Errorf("面板配置重建失败: %w", err)
	}
	appendModuleLog("ui reset from module dir")
	fmt.Println("ui reset")
	return nil
}

// tailFile 输出文件尾部 n 行。
func tailFile(path string, n int) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return err
	}
	const chunk = 64 * 1024
	var lines []string
	off := st.Size()
	for off > 0 && len(lines) <= n {
		sz := int64(chunk)
		if off < sz {
			sz = off
		}
		off -= sz
		buf := make([]byte, sz)
		if _, err := f.ReadAt(buf, off); err != nil && err != io.EOF {
			return err
		}
		lines = append(strings.Split(string(buf), "\n"), lines...)
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	for _, l := range lines {
		fmt.Println(l)
	}
	return nil
}
