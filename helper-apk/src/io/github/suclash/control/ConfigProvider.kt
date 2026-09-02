package io.github.suclash.control

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * 极简 ContentProvider（无 AndroidX）：把 config-export.yaml 以 content:// 暴露给外部
 * 编辑器读写，实现「用其他应用打开」。external-editor 通过 fd 直接读写本应用私有文件，
 * 无需其自身拥有文件系统权限。
 */
class ConfigProvider : ContentProvider() {

    companion object {
        /** 与 Manifest 中 provider authorities 一致 */
        const val AUTHORITY = "io.github.suclash.control.config"
    }

    private fun exportFile(): File {
        val ctx = context ?: error("ConfigProvider 未附加到 Context")
        return File(ctx.filesDir, "config-export.yaml")
    }

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "text/yaml"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val m = if (mode == "r") ParcelFileDescriptor.MODE_READ_ONLY
        else ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_CREATE
        return ParcelFileDescriptor.open(exportFile(), m)
    }

    override fun query(
        uri: Uri, projection: Array<out String>?,
        selection: String?, selectionArgs: Array<out String>?, sortOrder: String?
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri, values: ContentValues?,
        selection: String?, selectionArgs: Array<out String>?
    ): Int = 0
}
