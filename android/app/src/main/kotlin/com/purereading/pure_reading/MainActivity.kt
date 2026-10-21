package com.purereading.pure_reading

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "pure_reading/importer"
        private const val REQ_PICK_FOLDER = 4101
        private val IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp", "bmp", "gif")
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingDestDir: String? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImageFolderAndCopy" -> {
                        pendingResult = result
                        pendingDestDir = call.argument<String>("destDir")
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        startActivityForResult(intent, REQ_PICK_FOLDER)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_FOLDER) return
        if (resultCode != RESULT_OK || data?.data == null) {
            pendingResult?.success(null)
            pendingResult = null
            return
        }
        onFolderPicked(data.data!!)
    }

    private fun onFolderPicked(treeUri: Uri) {
        val dest = pendingDestDir
        val cb = pendingResult
        if (dest == null || cb == null) {
            pendingResult?.success(null)
            pendingResult = null
            return
        }
        // 枚举 + 复制全部放到后台线程，避免大目录阻塞 UI 线程（ANR / 卡死）。
        Thread {
            val images = enumerateImages(treeUri)
            val dir = File(dest)
            dir.mkdirs()
            val used = HashSet<String>()
            val copied = mutableListOf<String>()
            for ((name, uri) in images) {
                var base = name
                var n = 1
                while (!used.add(base)) {
                    val dot = base.lastIndexOf('.')
                    base = if (dot > 0) {
                        "${base.substring(0, dot)}_$n${base.substring(dot)}"
                    } else {
                        "${base}_$n"
                    }
                    n++
                }
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        File(dir, base).outputStream().use { output -> input.copyTo(output) }
                    }
                    copied.add(File(dir, base).absolutePath)
                } catch (_: Exception) {
                    // 单个文件失败不影响其余
                }
            }
            // 显示名可能带 provider 前缀（如 "xxx: Pictures/new-chat"），只保留最后一段
            val raw = queryDisplayName(treeUri) ?: treeUri.lastPathSegment ?: "folder"
            val folderName = raw.substringAfter(':').substringAfterLast('/').ifEmpty { raw }
            runOnUiThread {
                val result = if (copied.isEmpty()) {
                    null
                } else {
                    mapOf<String, Any>(
                        "folderName" to folderName,
                        "files" to copied
                    )
                }
                cb.success(result)
                pendingResult = null
            }
        }.start()
    }

    /// 通过 DocumentsContract 递归枚举 treeUri 下的全部图片文件。
    private fun enumerateImages(treeUri: Uri): List<Pair<String, Uri>> {
        val out = mutableListOf<Pair<String, Uri>>()
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val stack = ArrayDeque<String>()
        stack.add(rootId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        while (stack.isNotEmpty()) {
            val parentId = stack.removeLast()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            try {
                contentResolver.query(childrenUri, projection, null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val id = c.getString(0) ?: continue
                        val name = c.getString(1) ?: continue
                        val mime = c.getString(2) ?: ""
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            stack.add(id)
                        } else {
                            val ext = name.substringAfterLast('.', "").lowercase()
                            if (mime.startsWith("image/") || IMAGE_EXTS.contains(ext)) {
                                out.add(Pair(name, DocumentsContract.buildDocumentUriUsingTree(treeUri, id)))
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                // 无权限或异常的子目录跳过
            }
        }
        return out
    }

    private fun queryDisplayName(treeUri: Uri): String? {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        return try {
            contentResolver.query(treeUri, projection, null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
