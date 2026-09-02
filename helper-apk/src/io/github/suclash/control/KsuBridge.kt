package io.github.suclash.control

import android.content.Intent
import android.webkit.JavascriptInterface
import kotlinx.coroutines.launch

/**
 * 注入 WebView 的 root 桥，签名与 KernelSU 管理器一致（window.ksu.exec），
 * 使注入 zashboard 的悬浮面板同一套代码在两种环境下都能执行核心操作。
 *
 * 方法均由 WebView 的 JavaBridge 线程调用，exec 保持同步阻塞语义。
 */
class KsuBridge(private val activity: MainActivity) {

    @JavascriptInterface
    fun exec(cmd: String): String = Root.exec(cmd, 30).out

    @JavascriptInterface
    fun version(): String = "suclash-1.0"

    /** 悬浮面板「配置」按钮：打开配置管理界面。 */
    @JavascriptInterface
    fun openConfig() {
        appScope.launch(mainDispatcher) {
            activity.startActivity(
                Intent(activity, ConfigActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }
}
