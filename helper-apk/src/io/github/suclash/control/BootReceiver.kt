package io.github.suclash.control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 开机/应用更新后恢复常驻通知（静态通知，无前台服务，零耗电）。 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                TileState.sync(context)
        }
    }
}
