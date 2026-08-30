package io.github.ksuclash.control;

import android.content.Context;

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

    /** root 读取状态并刷新通知。 */
    public static void sync(Context c) {
        new Thread(() -> {
            String state = normalize(Root.ctl("status", 20));
            String detail = "";
            String panel = Root.ctl("panel", 20).trim();
            if (TILE_ON.equals(state)) {
                String out = Root.ctl("status", 20);
                java.util.regex.Matcher m = java.util.regex.Pattern
                        .compile("pid=(\\d+)").matcher(out);
                if (m.find() && !"-1".equals(m.group(1))) detail = "pid " + m.group(1);
                java.util.regex.Matcher mm = java.util.regex.Pattern
                        .compile("\"mode\":\"(\\w+)\"").matcher(out);
                if (mm.find()) detail = mm.group(1) + (detail.isEmpty() ? "" : " · " + detail);
            }
            final String st = state, dt = detail, pu = panel;
            MainActivity.mainHandler.post(() -> Notif.post(c, st, dt, pu));
        }, "ksuc-state").start();
    }
}
