package io.github.ksuclash.control;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** 通知按钮动作：执行 clashctl 后刷新通知与磁贴。 */
public class ActionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!"ksuc.CMD".equals(intent.getAction())) return;
        final String cmd = intent.getStringExtra("cmd");
        if (cmd == null || cmd.isEmpty()) return;

        final PendingResult pr = goAsync();
        new Thread(() -> {
            try {
                Root.ctl(cmd, 40);
                TileState.sync(context);
            } finally {
                pr.finish();
            }
        }, "ksuc-action").start();
    }
}
