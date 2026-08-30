package io.github.ksuclash.control;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.concurrent.TimeUnit;

/** su 执行封装。首次调用会触发 KernelSU 管理器的授权弹窗。 */
public final class Root {
    private static final String CTL = "/data/adb/modules/ksuclash/scripts/clashctl";

    public static class Result {
        public final int code;
        public final String out;
        public final String err;
        Result(int c, String o, String e) { code = c; out = o == null ? "" : o; err = e == null ? "" : e; }
        public boolean ok() { return code == 0; }
    }

    public interface Callback { void onResult(Result r); }

    /** 同步执行（勿在主线程调用）。 */
    public static Result exec(String cmd, int timeoutSec) {
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", cmd).start();
            boolean done = p.waitFor(timeoutSec, TimeUnit.SECONDS);
            if (!done) { p.destroyForcibly(); return new Result(-2, "", "timeout"); }
            String out = read(p.getInputStream());
            String err = read(p.getErrorStream());
            return new Result(p.exitValue(), out, err);
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
        }, "ksuc-root").start();
    }

    public static String ctl(String args, int timeoutSec) {
        return exec("sh " + CTL + " " + args, timeoutSec).out;
    }

    public static void ctlAsync(String args, Callback cb) {
        execAsync("sh " + CTL + " " + args, cb);
    }

    private static String read(java.io.InputStream is) throws Exception {
        BufferedReader r = new BufferedReader(new InputStreamReader(is, "UTF-8"));
        StringBuilder sb = new StringBuilder();
        char[] buf = new char[4096];
        int n;
        while ((n = r.read(buf)) > 0) sb.append(buf, 0, n);
        r.close();
        // 通过 stderr 无法区分时仍返回已读内容
        return sb.toString();
    }

    /** 额外读取 stderr（供错误提示用）。 */
    public static String execErr(String cmd) { return exec(cmd, 20).err; }

    /** 写 stdout 到外部（未使用，保留以扩展 OutputStream 语义）。 */
    @SuppressWarnings("unused")
    private static void noop(OutputStream o) { }
}
