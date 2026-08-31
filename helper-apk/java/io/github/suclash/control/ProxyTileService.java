package io.github.suclash.control;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** 控制中心磁贴：点按切换启停。 */
public class ProxyTileService extends TileService {

    @Override
    public void onStartListening() {
        super.onStartListening();
        refreshAsync();
    }

    @Override
    public void onClick() {
        refresh(TileState.TILE_STARTING);
        Root.ctlAsync("toggle", r -> {
            refreshAsync();
            // 状态文件写入可能有延迟，稍后再刷一次
            android.os.Handler h = new android.os.Handler(getMainLooper());
            h.postDelayed(this::refreshAsync, 1500);
        });
    }

    private void refreshAsync() {
        Root.execAsync("cat /data/adb/suclash/state/tile 2>/dev/null || echo off", r ->
                refresh(TileState.normalize(r.out)));
    }

    private void refresh(String state) {
        Tile t = getQsTile();
        if (t == null) return;
        boolean on = TileState.TILE_ON.equals(state) || TileState.TILE_STARTING.equals(state);
        t.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        if (TileState.TILE_STARTING.equals(state)) t.setSubtitle("启动中…");
        else if (TileState.TILE_PANIC.equals(state)) t.setSubtitle("已熔断");
        else t.setSubtitle(null);
        t.updateTile();
    }
}
