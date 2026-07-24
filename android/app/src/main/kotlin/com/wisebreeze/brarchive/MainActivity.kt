package com.wisebreeze.brarchive

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val channelName = "com.wisebreeze.brarchive/file_picker"
    private val permChannelName = "com.wisebreeze.brarchive/permissions"
    private val requestCodeFile = 1001
    private val requestCodeDir = 1002

    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingDirResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        val extensions = call.argument<List<String>>("extensions") ?: emptyList()
                        pendingFileResult = result
                        openFilePicker(extensions)
                    }
                    "pickDirectory" -> {
                        pendingDirResult = result
                        openDirectoryPicker()
                    }
                    "resolvePath" -> {
                        val uri = call.argument<String>("uri")
                        if (uri != null) {
                            val path = copyContentUriToCache(Uri.parse(uri))
                            result.success(path)
                        } else {
                            result.error("INVALID_URI", "uri is null", null)
                        }
                    }
                    "getDownloadsDirectory" -> {
                        val downloadsPath = getPublicDownloadsPath()
                        result.success(downloadsPath)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasStoragePermission" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(checkStoragePermission(path))
                    }
                    "requestStoragePermission" -> {
                        requestManageStoragePermission()
                        result.success(checkStoragePermission(""))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Checks if the app can read/write the given path.
    /// On Android 11+, MANAGE_EXTERNAL_STORAGE is required for paths outside
    /// app-specific dirs. On older versions, READ/WRITE_EXTERNAL_STORAGE.
    private fun checkStoragePermission(path: String): Boolean {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            android.os.Environment.isExternalStorageManager()
        } else {
            val readPerm = checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE)
            val writePerm = checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
            readPerm == android.content.pm.PackageManager.PERMISSION_GRANTED &&
            writePerm == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }

    /// Opens system settings to grant MANAGE_EXTERNAL_STORAGE (Android 11+)
    /// or requests READ/WRITE_EXTERNAL_STORAGE (Android 10 and below).
    private fun requestManageStoragePermission() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            try {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivity(intent)
            } catch (e: Exception) {
                val intent = Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                startActivity(intent)
            }
        } else {
            @Suppress("DEPRECATION")
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                ),
                2001
            )
        }
    }

    private fun openFilePicker(extensions: List<String>) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            if (extensions.isNotEmpty()) {
                val mimes = extensions.map { ext ->
                    when (ext.lowercase()) {
                        "zip" -> "application/zip"
                        "mcpack" -> "application/octet-stream"
                        else -> "application/octet-stream"
                    }
                }.toTypedArray()
                putExtra(Intent.EXTRA_MIME_TYPES, mimes)
            }
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestCodeFile)
        } catch (e: Exception) {
            pendingFileResult?.error("NO_ACTIVITY", e.message, null)
            pendingFileResult = null
        }
    }

    private fun openDirectoryPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestCodeDir)
        } catch (e: Exception) {
            pendingDirResult?.error("NO_ACTIVITY", e.message, null)
            pendingDirResult = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            requestCodeFile -> {
                if (resultCode == Activity.RESULT_OK && data?.data != null) {
                    val uri = data.data!!
                    val path = copyContentUriToCache(uri)
                    pendingFileResult?.success(path)
                } else {
                    pendingFileResult?.success(null)
                }
                pendingFileResult = null
            }
            requestCodeDir -> {
                if (resultCode == Activity.RESULT_OK && data?.data != null) {
                    val treeUri = data.data!!
                    val path = treeUriToPath(treeUri)
                    pendingDirResult?.success(path)
                } else {
                    pendingDirResult?.success(null)
                }
                pendingDirResult = null
            }
        }
    }

    /// Copies a content URI to the app cache and returns the real file path.
    private fun copyContentUriToCache(uri: Uri): String {
        val cursor = contentResolver.query(uri, null, null, null, null)
        var displayName = "picked_file"
        cursor?.use {
            val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && it.moveToFirst()) {
                displayName = it.getString(nameIndex)
            }
        }
        val cacheDir = File(cacheDir, "picked").apply { mkdirs() }
        val outFile = File(cacheDir, displayName)
        contentResolver.openInputStream(uri).use { input ->
            FileOutputStream(outFile).use { output ->
                input?.copyTo(output)
            }
        }
        return outFile.absolutePath
    }

    /// Best-effort conversion of a SAF tree URI to a real filesystem path.
    /// Falls back to the URI string if conversion fails.
    private fun treeUriToPath(treeUri: Uri): String {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        // docId is like "primary:Download/folder"
        if (docId.startsWith("primary:")) {
            val relative = docId.substringAfter("primary:")
            val externalStorage = android.os.Environment.getExternalStorageDirectory()
            return File(externalStorage, relative).absolutePath
        }
        return treeUri.toString()
    }

    /// Returns the public Downloads directory path.
    private fun getPublicDownloadsPath(): String {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            // Android 10+: use getExternalStoragePublicDirectory (deprecated but works)
            @Suppress("DEPRECATION")
            android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS
            ).absolutePath
        } else {
            @Suppress("DEPRECATION")
            android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS
            ).absolutePath
        }
    }
}
