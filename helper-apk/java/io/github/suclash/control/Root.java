package io.github.suclash.control;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.concurrent.TimeUnit;

/** su 执行封装。首次调用会触发 KernelSU 管理器的授权弹窗。 */
public final class Root {
    /** clashctl 脚本路径（App 内部与 JS 桥共用） */
    public static final String SCRIPT = "/data/adb/modules/suclash/scripts/clashctl";

    public static class Result {
        public final int code;
        public final String out;
        public final String err;
        Result(int c, String o, String e) { code = c; out = o == null ? "" : o; err = e == null ? "" : e; }
        public boolean ok() { return code == 0; }
    }

    public interface Callback { void onResult(Result r); }

    /** 同步执行（勿在主线程调用）。stderr 并入 stdout 返回。 */
    public static Result exec(String cmd, int timeoutSec) {
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start();
            // 独立线程持续排空输出：防止输出超出管道缓冲区时子进程写阻塞、waitFor 空等超时
            final Process proc = p;
            final StringBuilder buf = new StringBuilder();
            Thread drain = new Thread(() -> {
                try {
                    BufferedReader r = new BufferedReader(
                            new InputStreamReader(proc.getInputStream(), "UTF-8"));
                    char[] b = new char[4096];
                    int n;
                    while ((n = r.read(b)) > 0) buf.append(b, 0, n);
                } catch (Exception ignored) { }
            }, "suc-drain");
            drain.start();

            if (!p.waitFor(timeoutSec, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                return new Result(-2, "", "timeout");
            }
            drain.join(1000);
            return new Result(p.exitValue(), buf.toString(), "");
        } catch (Exception e) {
            return new Result(-1, "", e.toString());
        } finally {
            if (p != null) p.destroy();
        }
    }

    /** 异步执行并在主线程回调。 */
    public static void execAsync(String cmd, Callback cb) {
        new Thread(() -> {
            final Result r = exec(cmd, 30);
            if (cb != null) MainActivity.mainHandler.post(() -> cb.onResult(r));
        }, "suc-root").start();
    }

    public static String ctl(String args, int timeoutSec) {
        return exec("sh " + SCRIPT + " " + args, timeoutSec).out;
    }

    public static void ctlAsync(String args, Callback cb) {
        execAsync("sh " + SCRIPT + " " + args, cb);
    }
}
