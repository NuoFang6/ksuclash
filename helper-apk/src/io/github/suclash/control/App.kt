package io.github.suclash.control

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.android.asCoroutineDispatcher

/**
 * 应用级协程作用域：SupervisorJob 保证单个子协程失败不会取消兄弟任务。
 * 各组件（Activity/Service/Receiver）的异步工作统一在此发起，
 * 需要生命周期感知的界面（MainActivity）另建私有作用域并在 onDestroy 取消。
 */
val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/**
 * 主线程调度器：直接由主线程 Handler 构造，而非 Dispatchers.Main。
 * 后者经 ServiceLoader 探测工厂，R8 裁剪后 META-INF/services 会丢失导致运行时崩溃；
 * 直接引用的 HandlerContext 则必然保留，且行为与 Dispatchers.Main 完全一致。
 */
val mainDispatcher by lazy { Handler(Looper.getMainLooper()).asCoroutineDispatcher() }

/** clashctl status 输出中的 state= 字段（MainActivity / TileState / ConfigActivity 共用） */
internal val STATE_RE = Regex("""state=(\w+)""")

/** dp → px，供纯代码构建的 UI 使用 */
fun Context.dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

/** 短提示 */
fun Context.toast(s: String) {
    Toast.makeText(this, s, Toast.LENGTH_LONG).show()
}
