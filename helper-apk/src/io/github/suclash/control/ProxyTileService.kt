package io.github.suclash.control

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 控制中心磁贴：点按切换启停。 */
class ProxyTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refreshAsync()
    }

    override fun onClick() {
        refresh(TileState.TILE_STARTING)
        Root.ctlAsync("toggle") {
            refreshAsync()
            // 状态文件写入可能有延迟，稍后再刷一次
            appScope.launch(mainDispatcher) {
                delay(1_500)
                refreshAsync()
            }
        }
    }

    private fun refreshAsync() {
        Root.execAsync("cat /data/adb/suclash/state/tile 2>/dev/null || echo off") { r ->
            refresh(TileState.normalize(r.out))
        }
    }

    private fun refresh(state: String) {
        val t = qsTile ?: return
        val on = state == TileState.TILE_ON || state == TileState.TILE_STARTING
        t.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 31) {
            t.subtitle = when (state) {
                TileState.TILE_STARTING -> "启动中…"
                TileState.TILE_PANIC -> "已熔断"
                else -> null
            }
        }
        t.updateTile()
    }
}
