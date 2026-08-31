package io.github.suclash.control;

import android.webkit.JavascriptInterface;

/** 注入 WebView 的 root 桥，签名与 KernelSU 管理器一致（window.ksu.exec），
 *  使注入 zashboard 的悬浮面板同一套代码在两种环境下都能执行核心操作。 */
public class KsuBridge {
    private final MainActivity activity;

    KsuBridge(MainActivity a) { this.activity = a; }

    @JavascriptInterface
    public String exec(String cmd) {
        return Root.exec(cmd, 30).out;
    }

    @JavascriptInterface
    public String version() {
        return "suclash-1.0";
    }

    /** 悬浮面板「配置」按钮：打开配置管理界面。 */
    @JavascriptInterface
    public void openConfig() {
        MainActivity.mainHandler.post(() -> {
            android.content.Intent i = new android.content.Intent(activity, ConfigActivity.class);
            i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(i);
        });
    }
}
