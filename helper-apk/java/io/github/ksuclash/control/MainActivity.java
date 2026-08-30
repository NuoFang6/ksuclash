package io.github.ksuclash.control;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/** 控制台：状态、启停、模式、自启开关、日志。 */
public class MainActivity extends Activity {
    public static final Handler mainHandler = new Handler(Looper.getMainLooper());

    private TextView status;
    private TextView log;
    private Switch autostart;
    private boolean hasRoot = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestNotifPermission();
        buildUi();
        refresh();
    }

    @Override
    protected void onResume() { super.onResume(); refresh(); }

    private void requestNotifPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
    }

    private Button btn(String text, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(text);
        b.setOnClickListener(l);
        return b;
    }

    private LinearLayout row(LinearLayout parent) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(8);
        r.setLayoutParams(lp);
        parent.addView(r);
        return r;
    }

    private void addTo(LinearLayout rowView, Button b) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        lp.setMargins(dp(4), 0, dp(4), 0);
        rowView.addView(b, lp);
    }

    private int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density); }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(16), dp(16), dp(16));
        scroll.addView(root, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(scroll);

        TextView title = new TextView(this);
        title.setText("⚡ KSU Clash 控制台");
        title.setTextSize(18);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        status = new TextView(this);
        status.setPadding(0, dp(10), 0, dp(4));
        status.setText("读取状态中…");
        status.setTextSize(13);
        root.addView(status);

        LinearLayout r1 = row(root);
        addTo(r1, btn("启动", v -> ctl("start")));
        addTo(r1, btn("停止", v -> ctl("stop")));
        addTo(r1, btn("重启", v -> ctl("restart")));

        LinearLayout r2 = row(root);
        addTo(r2, btn("规则模式", v -> ctl("mode rule")));
        addTo(r2, btn("全局模式", v -> ctl("mode global")));
        addTo(r2, btn("直连模式", v -> ctl("mode direct")));

        autostart = new Switch(this);
        autostart.setText("开机自启");
        autostart.setPadding(dp(4), dp(10), 0, dp(4));
        autostart.setOnCheckedChangeListener((b, on) ->
                ctl(on ? "enable" : "disable"));
        root.addView(autostart);

        LinearLayout r3 = row(root);
        addTo(r3, btn("打开 zashboard 面板", v -> openPanel()));
        addTo(r3, btn("刷新日志", v -> tailLog()));

        log = new TextView(this);
        log.setTypeface(Typeface.MONOSPACE);
        log.setTextSize(10);
        log.setPadding(dp(8), dp(8), dp(8), dp(8));
        log.setBackgroundColor(0x22000000);
        log.setMovementMethod(new ScrollingMovementMethod());
        log.setText("(日志)");
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(180));
        lp.topMargin = dp(10);
        root.addView(log, lp);

        TextView hint = new TextView(this);
        hint.setTextSize(11);
        hint.setPadding(dp(4), dp(8), 0, 0);
        hint.setText("若无法 root：请在 KernelSU 管理器「超级用户」中授权本应用。\n面板也可用手机浏览器访问 http://127.0.0.1:9090/ui/");
        root.addView(hint);
    }

    private void ctl(String args) {
        Toast.makeText(this, "执行: " + args, Toast.LENGTH_SHORT).show();
        Root.ctlAsync(args, r -> {
            if (!r.ok() && r.err.contains("Permission denied"))
                toast("root 被拒绝，请在管理器中授权");
            mainHandler.postDelayed(this::refresh, 500);
        });
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_LONG).show();
    }

    private String panelUrl = null;

    private void openPanel() {
        Root.ctlAsync("panel", r -> {
            String url = r.out == null ? "" : r.out.trim();
            if (url.startsWith("http://")) panelUrl = url;
            try {
                android.content.Intent i = new android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse(panelUrl != null ? panelUrl : "http://127.0.0.1:9090/ui/"));
                i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
            } catch (Exception e) {
                toast("没有可用的浏览器: " + e.getMessage());
            }
        });
    }

    private void refresh() {
        Root.execAsync("sh /data/adb/modules/ksuclash/scripts/clashctl status; "
                + "cat /data/adb/ksuclash/state/enabled 2>/dev/null; "
                + "cat /data/adb/ksuclash/state/panic 2>/dev/null", r -> {
            hasRoot = r.ok() || (r.out != null && r.out.contains("state="));
            String out = r.out == null ? "" : r.out;
            if (!hasRoot) {
                status.setText("⚠ 无法连接 root shell\n" + r.err
                        + "\n\n请在 KernelSU 管理器中授权本应用后重试。");
                return;
            }
            String[] lines = out.split("\n");
            String st = lines.length > 0 ? lines[0] : "";
            String tile = st.replaceFirst("^state=", "状态: ");
            status.setText(tile + (st.startsWith("state=panic") ? "\n(看门狗已熔断，可点「启动」恢复)" : ""));
            boolean auto = false;
            for (String l : lines) {
                if (l.trim().equals("1")) { auto = true; break; }
            }
            autostart.setOnCheckedChangeListener(null);
            autostart.setChecked(auto);
            autostart.setOnCheckedChangeListener((b, on) -> ctl(on ? "enable" : "disable"));
            tailLog();
        });
    }

    private void tailLog() {
        Root.execAsync("tail -60 /data/adb/ksuclash/logs/mihomo.log 2>/dev/null; "
                + "echo ---module.log---; "
                + "tail -10 /data/adb/ksuclash/module.log 2>/dev/null", r ->
                mainHandler.post(() -> log.setText(r.out == null || r.out.isEmpty() ? "(暂无日志)" : r.out)));
    }
}
