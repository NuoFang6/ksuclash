package io.github.suclash.control;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileNotFoundException;

/**
 * 极简 ContentProvider（无 AndroidX）：把 config-export.yaml 以 content:// 暴露给外部
 * 编辑器读写，实现「用其他应用打开」。external-editor 通过 fd 直接读写本应用私有文件，
 * 无需其自身拥有文件系统权限。
 */
public class ConfigProvider extends ContentProvider {
    static final String AUTHORITY = "io.github.suclash.control.config";

    private File exportFile() {
        return new File(getContext().getFilesDir(), "config-export.yaml");
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return "text/yaml";
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        int m = "r".equals(mode) ? ParcelFileDescriptor.MODE_READ_ONLY
                : ParcelFileDescriptor.MODE_READ_WRITE | ParcelFileDescriptor.MODE_CREATE;
        return ParcelFileDescriptor.open(exportFile(), m);
    }

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
