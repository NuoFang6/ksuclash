package io.github.ksuclash.control;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * KSU Clash 主界面：核心运行中 → 全屏 WebView 加载 zashboard（注入与 KSU 管理器
 * 同名的 ksu root 桥，悬浮面板同一套代码）；核心未运行 → 原生提示页（启动核心）。
 */
public class MainActivity extends Activity {
    public static final android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());

    private WebView web;
    private ViewGroup hintView;
    private String panelUrl = null;
    private boolean started = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestNotifPermission();
        refreshEntry();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (!started) refreshEntry();
        TileState.sync(this);
    }

    private void requestNotifPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                        != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
    }

    /** 读取核心状态，决定进入 webview 还是提示页。 */
    private void refreshEntry() {
        Root.execAsync("sh " + Root.SCRIPT + " status; sh " + Root.SCRIPT + " panel", r -> {
            String out = r.out == null ? "" : r.out;
            java.util.regex.Matcher sm = java.util.regex.Pattern
                    .compile("state=(\\w+)").matcher(out);
            String st = sm.find() ? sm.group(1) : "noroot";
            String url = null;
            java.util.regex.Matcher pm = java.util.regex.Pattern
                    .compile("panel=(http\\S+)").matcher(out);
            if (pm.find()) url = pm.group(1);
            final String state = st, purl = url;
            mainHandler.post(() -> {
                if ("on".equals(state) && purl != null) {
                    showWeb(purl);
                } else {
                    showHint("noroot".equals(state) ? "无法连接 root shell\n\n请在 KernelSU 管理器中授权本应用后重试。"
                            : "核心未运行\n\n启动后自动进入 zashboard 面板。");
                }
            });
        });
    }

    private void showHint(String text) {
        started = false;
        setContentView(buildHint(text));
    }

    private View buildHint(String text) {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(20), dp(20), dp(20));
        scroll.addView(root, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        hintView = root;

        TextView title = new TextView(this);
        title.setText("⚡ KSU Clash  [mihomo]");
        title.setTextSize(19);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView status = new TextView(this);
        status.setText(text);
        status.setTextSize(14);
        status.setPadding(0, dp(16), 0, dp(4));
        root.addView(status);

        Button start = new Button(this);
        start.setText("启动核心");
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(16);
        start.setLayoutParams(lp);
        start.setOnClickListener(v -> startCore());
        root.addView(start);

        Button reload = new Button(this);
        reload.setText("重新检测");
        reload.setOnClickListener(v -> refreshEntry());
        root.addView(reload);

        TextView hint = new TextView(this);
        hint.setTextSize(11.5f);
        hint.setPadding(0, dp(12), 0, 0);
        hint.setText("提示：若启动按钮无效，请在 KernelSU 管理器「超级用户」中授权本应用。\n核心运行后本应用即 zashboard 面板，核心启停等操作在面板右下角悬浮窗中。");
        root.addView(hint);
        return scroll;
    }

    private void startCore() {
        Toast.makeText(this, "正在启动核心…", Toast.LENGTH_SHORT).show();
        Root.ctlAsync("start", r -> mainHandler.postDelayed(this::refreshEntry, 800));
    }

    private void showWeb(String url) {
        started = true;
        panelUrl = url;
        web = new WebView(this);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setCacheMode(android.webkit.WebSettings.LOAD_NO_CACHE);
        web.setBackgroundColor(0xFF0F172A);
        web.addJavascriptInterface(new KsuBridge(), "ksu");
        web.setWebViewClient(new WebViewClient());
        setContentView(web);
        web.loadUrl(url);
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }

    private int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density); }
}
