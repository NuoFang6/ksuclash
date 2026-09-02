package io.github.suclash.control

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/** su 执行封装。首次调用会触发 KernelSU 管理器的授权弹窗。 */
object Root {
    /** clashctl 脚本路径（App 内部与 JS 桥共用） */
    const val SCRIPT = "/data/adb/modules/suclash/scripts/clashctl"

    private const val DEFAULT_TIMEOUT_SEC = 30

    /** 执行结果：code==0 成功；-2 超时；-1 启动失败/异常 */
    data class Result(val code: Int, val out: String, val err: String) {
        val ok: Boolean get() = code == 0

        companion object {
            fun fail(code: Int, err: String) = Result(code, "", err)
        }
    }

    /**
     * 同步执行（勿在主线程调用）。stderr 并入 stdout 返回。
     * 用独立线程排空输出：防止输出超出管道缓冲区时子进程写阻塞、waitFor 空等超时。
     */
    fun exec(cmd: String, timeoutSec: Int = DEFAULT_TIMEOUT_SEC): Result {
        val p = try {
            ProcessBuilder("su", "-c", cmd)
                .redirectErrorStream(true)
                .start()
        } catch (e: Exception) {
            return Result.fail(-1, e.toString())
        }

        val buf = StringBuilder()
        val drain = Thread({
            try {
                p.inputStream.bufferedReader(Charsets.UTF_8).use { r ->
                    val b = CharArray(4096)
                    while (true) {
                        val n = r.read(b)
                        if (n <= 0) break
                        buf.append(b, 0, n)
                    }
                }
            } catch (_: Exception) {
                // 子进程被销毁时管道关闭属正常路径
            }
        }, "suc-drain")

        try {
            drain.start()
            if (!p.waitFor(timeoutSec.toLong(), TimeUnit.SECONDS)) {
                p.destroyForcibly()
                return Result.fail(-2, "timeout")
            }
            drain.join(1_000)
            return Result(p.exitValue(), buf.toString(), "")
        } catch (e: Exception) {
            return Result.fail(-1, e.toString())
        } finally {
            p.destroy()
        }
    }

    /**
     * 异步执行并在主线程回调。
     * 结果统一经 mainDispatcher 派发，等价于旧实现的 mainHandler.post。
     */
    fun execAsync(cmd: String, onResult: (Result) -> Unit) {
        appScope.launch {
            val r = withContext(Dispatchers.IO) { exec(cmd) }
            withContext(mainDispatcher) { onResult(r) }
        }
    }

    /** 执行 clashctl 子命令，返回 stdout */
    fun ctl(args: String, timeoutSec: Int): String =
        exec("sh $SCRIPT $args", timeoutSec).out

    /** 异步执行 clashctl 子命令，完整 Result 回调主线程 */
    fun ctlAsync(args: String, onResult: (Result) -> Unit): Unit =
        execAsync("sh $SCRIPT $args", onResult)
}
