package io.github.suclash.control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** 通知按钮动作：执行 clashctl 后刷新通知与磁贴。 */
class ActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Notif.ACTION_CMD) return
        val cmd = intent.getStringExtra("cmd")?.takeIf { it.isNotEmpty() } ?: return

        // goAsync 拉长广播生命周期，异步完成后 finish
        val pending = goAsync()
        appScope.launch(Dispatchers.IO) {
            try {
                Root.ctl(cmd, 40)
                TileState.sync(context)
            } finally {
                pending.finish()
            }
        }
    }
}
