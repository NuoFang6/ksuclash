package io.github.ksuclash.control;

import android.webkit.JavascriptInterface;

/** 注入 WebView 的 root 桥，签名与 KernelSU 管理器一致（window.ksu.exec），
 *  使注入 zashboard 的悬浮面板同一套代码在两种环境下都能执行核心操作。 */
public class KsuBridge {
    @JavascriptInterface
    public String exec(String cmd) {
        return Root.exec(cmd, 30).out;
    }

    @JavascriptInterface
    public String version() {
        return "ksuclash-1.0";
    }
}
