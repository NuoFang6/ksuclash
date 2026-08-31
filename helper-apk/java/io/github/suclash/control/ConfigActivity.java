package io.github.suclash.control;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 配置管理：临时编辑器 + 导入配置文件 + 用其他应用打开。
 * 配置源文件 /data/adb/suclash/config.yaml 由 root 读写，核心运行中应用时走 clashctl reload（SIGHUP）。
 */
public class ConfigActivity extends Activity {
    static final String CFG = "/data/adb/suclash/config.yaml";
    static final int REQ_IMPORT = 1;
    static final int REQ_EXTERNAL = 2;

    private TextView status;
    private EditText editor;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        showMain();
    }

    // ---------------- 视图 ----------------

    private void showMain() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(16), dp(18), dp(16));

        TextView title = new TextView(this);
        title.setText("⚡ 配置管理");
        title.setTextSize(18);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        root.addView(title);

        status = new TextView(this);
        status.setPadding(0, dp(8), 0, dp(8));
        status.setTextSize(13);
        root.addView(status);

        root.addView(btn("编辑配置", v -> showEditor()));
        root.addView(btn("导入配置文件", v -> pickFile()));
        root.addView(btn("用其他应用打开", v -> openExternal()));
        root.addView(btn("重新导入外部编辑", v -> reimportExternal()));
        root.addView(btn("重置 UI（从模块目录恢复面板）", v -> {
            Root.Result r = Root.exec("sh " + Root.SCRIPT + " reset-ui", 30);
            toast(r.ok() ? r.out.trim() : "重置失败：" + r.err);
            refreshStatus();
        }));
        root.addView(btn("返回", v -> finish()));

        ScrollView sv = new ScrollView(this);
        sv.addView(root, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(sv);
        refreshStatus();
    }

    private void showEditor() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(12), dp(12), dp(12));

        TextView hint = new TextView(this);
        hint.setText("编辑 " + CFG + "\n保存后核心运行中则自动重载，否则启动时生效。");
        hint.setTextSize(12);
        hint.setPadding(0, 0, 0, dp(8));
        root.addView(hint);

        editor = new EditText(this);
        editor.setGravity(Gravity.TOP | Gravity.START);
        editor.setTypeface(android.graphics.Typeface.MONOSPACE);
        editor.setTextSize(12);
        editor.setHorizontallyScrolling(false);
        String content = readConfig();
        editor.setText(content == null ? "" : content);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        root.addView(editor, lp);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(btn("保存并应用", v -> {
            String r = apply(editor.getText().toString());
            toast(r);
            showMain();
        }));
        row.addView(btn("取消", v -> showMain()));
        root.addView(row);

        setContentView(root);
    }

    private Button btn(String label, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(6);
        b.setLayoutParams(lp);
        b.setOnClickListener(l);
        return b;
    }

    // ---------------- 数据读写 ----------------

    private String readConfig() {
        Root.Result r = Root.exec("cat " + CFG, 20);
        return r.ok() ? r.out : null;
    }

    /** 写私有临时文件，再经 root 覆盖到数据目录；运行中则重载。 */
    private String apply(String content) {
        File tmp = new File(getFilesDir(), "config-import.yaml");
        try {
            writeFile(tmp, content);
        } catch (IOException e) {
            return "写临时文件失败：" + e;
        }
        Root.Result w = Root.exec("cat '" + tmp.getAbsolutePath() + "' > " + CFG + " && chmod 644 " + CFG, 30);
        if (!w.ok()) return "写入配置失败（无 root？）";
        if ("on".equals(state())) {
            Root.Result r = Root.exec("sh " + Root.SCRIPT + " reload", 30);
            return "已保存并重载：" + r.out.trim();
        }
        return "已保存（核心未运行，启动后生效）";
    }

    private String state() {
        Root.Result r = Root.exec("sh " + Root.SCRIPT + " status", 20);
        Matcher m = Pattern.compile("state=(\\w+)").matcher(r.out);
        return m.find() ? m.group(1) : "off";
    }

    private void refreshStatus() {
        String st = state();
        String t = "核心：" + (("on".equals(st) ? "运行中" : ("panic".equals(st) ? "已熔断" : "已停止")));
        t += "\n配置：" + CFG;
        status.setText(t);
    }

    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_LONG).show(); }

    // ---------------- 导入 ----------------

    private void pickFile() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        try { startActivityForResult(i, REQ_IMPORT); }
        catch (Exception e) { toast("无法打开文件选择器"); }
    }

    // ---------------- 用其他应用打开 ----------------

    private void openExternal() {
        String content = readConfig();
        if (content == null) { toast("读取配置失败"); return; }
        File f = new File(getFilesDir(), "config-export.yaml");
        try { writeFile(f, content); } catch (IOException e) { toast("导出失败：" + e); return; }

        Intent i = new Intent(Intent.ACTION_EDIT);
        i.setDataAndType(Uri.parse("content://" + ConfigProvider.AUTHORITY + "/config"), "text/yaml");
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        try { startActivityForResult(i, REQ_EXTERNAL); }
        catch (Exception e) { toast("未找到可编辑 YAML 的应用"); }
    }

    private void reimportExternal() {
        File f = new File(getFilesDir(), "config-export.yaml");
        if (!f.exists()) { toast("尚无外部编辑导出，请先「用其他应用打开」"); return; }
        try {
            String r = apply(readFile(f));
            toast(r);
            refreshStatus();
        } catch (IOException e) { toast("读取外部编辑失败：" + e); }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (res != RESULT_OK || data == null) return;
        if (req == REQ_IMPORT) {
            Uri u = data.getData();
            if (u == null) return;
            try {
                String content = readUri(u);
                if (content == null) { toast("读取所选文件失败"); return; }
                String r = apply(content);
                toast(r);
                refreshStatus();
            } catch (IOException e) { toast("导入失败：" + e); }
        } else if (req == REQ_EXTERNAL) {
            toast("已从外部编辑返回，点「重新导入外部编辑」应用");
        }
    }

    private String readUri(Uri u) throws IOException {
        java.io.InputStream in = getContentResolver().openInputStream(u);
        if (in == null) return null;
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        in.close();
        return bo.toString("UTF-8");
    }

    // ---------------- 工具 ----------------

    private static void writeFile(File f, String s) throws IOException {
        FileOutputStream fo = new FileOutputStream(f);
        fo.write(s.getBytes(StandardCharsets.UTF_8));
        fo.close();
    }

    private static String readFile(File f) throws IOException {
        FileInputStream fi = new FileInputStream(f);
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = fi.read(buf)) > 0) bo.write(buf, 0, n);
        fi.close();
        return bo.toString("UTF-8");
    }

    private int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density); }
}
