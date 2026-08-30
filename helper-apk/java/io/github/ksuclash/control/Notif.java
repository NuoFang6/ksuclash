package io.github.ksuclash.control;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;

/** 常驻通知：静态通知（无前台服务），动作经 ActionReceiver 执行。 */
public final class Notif {
    static final String CHANNEL = "ksuc_core";
    static final int ID = 1001;

    static NotificationManager nm(Context c) {
        return (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    }

    static void ensureChannel(Context c) {
        NotificationChannel ch = new NotificationChannel(CHANNEL,
                c.getString(R.string.notif_channel), NotificationManager.IMPORTANCE_MIN);
        ch.setDescription("KSU Clash 快捷操作");
        ch.setShowBadge(false);
        nm(c).createNotificationChannel(ch);
    }

    static PendingIntent action(Context c, String cmd) {
        Intent i = new Intent(c, ActionReceiver.class).setAction("ksuc.CMD").putExtra("cmd", cmd);
        int req = cmd.hashCode();
        return PendingIntent.getBroadcast(c, req, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static PendingIntent openApp(Context c) {
        Intent i = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        if (i == null) return null;
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return PendingIntent.getActivity(c, 7, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static PendingIntent openPanel(Context c, String url) {
        if (url == null || url.isEmpty()) url = "http://127.0.0.1:9090/ui/";
        Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            return PendingIntent.getActivity(c, 8, i,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        } catch (Exception e) { return null; }
    }

    /** 依据状态文件构建/刷新通知。state: on|off|starting|stopping|panic；panelUrl 可为 null（用默认） */
    public static void post(Context c, String state, String detail, String panelUrl) {
        ensureChannel(c);
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) b = new Notification.Builder(c, CHANNEL);
        else b = new Notification.Builder(c);
        b.setSmallIcon(R.drawable.ic_tile)
                .setContentTitle(c.getString(R.string.notif_title))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(openApp(c))
                .setShowWhen(false);

        String text;
        if ("on".equals(state)) text = "运行中" + (detail == null ? "" : " · " + detail);
        else if ("panic".equals(state)) text = "已熔断（多次崩溃自动停止）";
        else if ("starting".equals(state)) text = "启动中…";
        else if ("stopping".equals(state)) text = "停止中…";
        else text = "已停止";

        b.setContentText(text);

        if ("on".equals(state)) {
            b.addAction(new Notification.Action.Builder(null, "暂停(直连)", action(c, "mode direct")).build());
            b.addAction(new Notification.Action.Builder(null, "重启核心", action(c, "restart")).build());
            PendingIntent p = openPanel(c, panelUrl);
            if (p != null) b.addAction(new Notification.Action.Builder(null, "面板", p).build());
        } else if ("panic".equals(state)) {
            b.addAction(new Notification.Action.Builder(null, "恢复并启动", action(c, "resume")).build());
        } else {
            b.addAction(new Notification.Action.Builder(null, "启动", action(c, "start")).build());
        }

        try { nm(c).notify(ID, b.build()); } catch (SecurityException ignored) { }
    }

    public static void cancel(Context c) { nm(c).cancel(ID); }
}
