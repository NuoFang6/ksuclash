package io.github.suclash.control;

import android.content.Context;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** 磁贴/通知共用的状态语义。 */
public final class TileState {
    public static final String TILE_ON = "on";
    public static final String TILE_OFF = "off";
    public static final String TILE_STARTING = "starting";
    public static final String TILE_STOPPING = "stopping";
    public static final String TILE_PANIC = "panic";

    public static String normalize(String raw) {
        String s = raw == null ? "" : raw.trim();
        switch (s) {
            case TILE_ON:
            case TILE_STARTING:
            case TILE_STOPPING:
            case TILE_PANIC:
                return s;
            default:
                return TILE_OFF;
        }
    }

    /** 从 clashctl status 全文输出中提取 state= 值 */
    private static String parseState(String statusOut) {
        Matcher m = Pattern.compile("state=(\\w+)").matcher(statusOut);
        return normalize(m.find() ? m.group(1) : "");
    }

    /** root 读取状态并刷新通知。 */
    public static void sync(Context c) {
        new Thread(() -> {
            String out = Root.ctl("status", 20);
            String state = parseState(out);
            String detail = "";
            if (TILE_ON.equals(state)) {
                Matcher m = Pattern.compile("pid=(\\d+)").matcher(out);
                if (m.find() && !"-1".equals(m.group(1))) detail = "pid " + m.group(1);
                Matcher mm = Pattern.compile("mode=(\\w+)").matcher(out);
                if (mm.find()) detail = mm.group(1) + (detail.isEmpty() ? "" : " · " + detail);
            }
            final String st = state, dt = detail;
            MainActivity.mainHandler.post(() -> Notif.post(c, st, dt));
        }, "suc-state").start();
    }
}
