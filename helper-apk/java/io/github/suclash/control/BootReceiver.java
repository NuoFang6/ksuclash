package io.github.suclash.control;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** 开机/应用更新后恢复常驻通知（静态通知，无前台服务，零耗电）。 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String a = intent.getAction();
        if (a == null) return;
        if (!Intent.ACTION_BOOT_COMPLETED.equals(a)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) return;
        TileState.sync(context);
    }
}
