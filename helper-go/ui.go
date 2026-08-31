package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"strings"
)

// UI 相关：面板地址、面板自愈注入、从模块安装目录恢复面板。

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

// cmdResetUI 从模块安装目录恢复被破坏的面板（升级面板失败/文件损坏时使用）。
func cmdResetUI(args []string) error {
	syncUIFromModule()
	if err := doPatch(); err != nil {
		return fmt.Errorf("面板配置重建失败: %w", err)
	}
	appendModuleLog("ui reset from module dir")
	fmt.Println("ui reset")
	return nil
}

// cmdRepatchUI 面板自愈注入：panel.js / panel-config.js / index.html 注入点。
// 幂等；zashboard 自升级（POST /upgrade/ui 清空目录）后由前端 hook 调用。
func cmdRepatchUI(args []string) error {
	index := dataUIDir + "/index.html"
	if _, err := os.Stat(index); err != nil {
		// 数据目录面板整个没了 → 全量恢复
		syncUIFromModule()
		_ = doPatch()
		appendModuleLog("ui missing, full resync")
		fmt.Println("ui resynced")
		return nil
	}

	// 1. 悬浮面板脚本补回
	if _, err := os.Stat(dataUIDir + "/panel.js"); err != nil {
		if b, err := os.ReadFile(modUIDir + "/panel.js"); err == nil {
			_ = os.WriteFile(dataUIDir + "/panel.js", b, 0o644)
		}
	}
	// 2. 面板配置（API 地址 + secret）补回，与 runtime 保持一致
	if _, err := os.Stat(dataUIDir + "/panel-config.js"); err != nil {
		_ = doPatch()
	}
	// 3. index.html 注入点检查（已注入则跳过）
	b, err := os.ReadFile(index)
	if err != nil {
		return err
	}
	if strings.Contains(string(b), `src="./panel.js"`) {
		return nil
	}
	if !strings.Contains(string(b), "</body>") {
		// 无 </body>（异常结构）：追加到文件尾
		inj := []byte(`\n<script src="./panel-config.js"></script><script src="./panel.js"></script>\n`)
		f, err := os.OpenFile(index, os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			return err
		}
		defer f.Close()
		_, _ = f.Write(inj)
		appendModuleLog("ui re-patched (appended, no </body>)")
		fmt.Println("repatched")
		return nil
	}
	inject := `<script src="./panel-config.js"></script><script src="./panel.js"></script>`
	content := string(b)
	i := strings.Index(content, "</body>")
	if i < 0 {
		return nil
	}
	out := content[:i] + inject + content[i:]
	tmp := index + ".tmp"
	if err := os.WriteFile(tmp, []byte(out), 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, index); err != nil {
		return err
	}
	appendModuleLog("ui re-patched (zashboard 升级后自愈注入)")
	fmt.Println("repatched")
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
