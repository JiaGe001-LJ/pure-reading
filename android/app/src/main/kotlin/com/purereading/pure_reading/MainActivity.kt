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
        private val BOOK_EXTS = IMAGE_EXTS + "pdf"
        // 压缩包 / 电子书容器：DocumentsUI 会把这类“文件”展开成虚拟目录，
        // 误选后枚举内部大量小文件会卡死。碰到直接跳过，不展开、不收录。
        private val CONTAINER_EXTS =
            setOf("mobi", "epub", "azw", "azw3", "zip", "rar", "7z", "cbz", "cbr", "tar", "gz")
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingDestDir: String? = null
    private var pendingMode = "img" // "img" = 仅图片平铺；"book" = 图片+pdf，保留目录层级

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImageFolderAndCopy" -> {
                        pendingMode = "img"
                        pendingResult = result
                        pendingDestDir = call.argument<String>("destDir")
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQ_PICK_FOLDER)
                    }
                    "pickBookFolderAndCopy" -> {
                        pendingMode = "book"
                        pendingResult = result
                        pendingDestDir = call.argument<String>("destDir")
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQ_PICK_FOLDER)
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
        val mode = pendingMode
        if (dest == null || cb == null) {
            pendingResult?.success(null)
            pendingResult = null
            return
        }
        // 枚举 + 复制全部放到后台线程，避免大目录阻塞 UI 线程（ANR / 卡死）。
        Thread {
            val files = if (mode == "img") enumerateImages(treeUri) else enumerateBookFiles(treeUri)
            val dir = File(dest)
            dir.mkdirs()
            val used = HashSet<String>()
            val copied = mutableListOf<Pair<String, String>>() // (rel, absPath)
            for ((rel, name, uri) in files) {
                var base = name
                var n = 1
                while (!used.add(relOf(base, rel))) {
                    val dot = base.lastIndexOf('.')
                    base = if (dot > 0) {
                        "${base.substring(0, dot)}_$n${base.substring(dot)}"
                    } else {
                        "${base}_$n"
                    }
                    n++
                }
                try {
                    val targetDir = if (rel.contains('/')) {
                        File(dir, rel.substringBeforeLast('/')).apply { mkdirs() }
                    } else dir
                    contentResolver.openInputStream(uri)?.use { input ->
                        File(targetDir, base).outputStream().use { output -> input.copyTo(output) }
                    }
                    copied.add(Pair(
                        if (rel.contains('/')) "${rel.substringBeforeLast('/')}/$base" else base,
                        File(targetDir, base).absolutePath
                    ))
                } catch (_: Exception) {
                    // 单个文件失败不影响其余
                }
            }
            // 显示名可能带 provider 前缀（如 "xxx: Pictures/new-chat"），只保留最后一段
            val raw = queryDisplayName(treeUri) ?: treeUri.lastPathSegment ?: "folder"
            val folderName = raw.substringAfter(':').substringAfterLast('/').ifEmpty { raw }
            runOnUiThread {
                val result: Map<String, Any>? = if (copied.isEmpty()) {
                    null
                } else if (mode == "img") {
                    mapOf(
                        "folderName" to folderName,
                        "files" to copied.map { it.second }
                    )
                } else {
                    mapOf(
                        "folderName" to folderName,
                        "files" to copied.map { mapOf("rel" to it.first, "path" to it.second) }
                    )
                }
                cb.success(result)
                pendingResult = null
            }
        }.start()
    }

    private fun relOf(base: String, rel: String): String =
        if (rel.contains('/')) "${rel.substringBeforeLast('/')}/$base" else base

    /// 是否为压缩包/电子书容器（mobi/epub/zip 等）。这类“目录”是 DocumentsUI
    /// 展开的虚拟目录，枚举内部会卡，直接跳过。
    private fun isContainerDir(name: String): Boolean {
        val ext = name.substringAfterLast('.', "").lowercase()
        return CONTAINER_EXTS.contains(ext)
    }

    /// 仅枚举图片（平铺路径，兼容旧的“整目录图片漫画”导入）。
    private fun enumerateImages(treeUri: Uri): List<Triple<String, String, Uri>> {
        val out = mutableListOf<Triple<String, String, Uri>>()
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
                            if (!isContainerDir(name)) stack.add(id)
                        } else {
                            val ext = name.substringAfterLast('.', "").lowercase()
                            if (mime.startsWith("image/") || IMAGE_EXTS.contains(ext)) {
                                out.add(Triple(name, name, DocumentsContract.buildDocumentUriUsingTree(treeUri, id)))
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

    /// 枚举图片 + PDF，保留相对目录层级（子文件夹 = 章节）。
    private fun enumerateBookFiles(treeUri: Uri): List<Triple<String, String, Uri>> {
        val out = mutableListOf<Triple<String, String, Uri>>()
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val stack = ArrayDeque<Pair<String, String>>() // (docId, relPath)
        stack.add(Pair(rootId, ""))
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        while (stack.isNotEmpty()) {
            val (parentId, rel) = stack.removeLast()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            try {
                contentResolver.query(childrenUri, projection, null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val id = c.getString(0) ?: continue
                        val name = c.getString(1) ?: continue
                        val mime = c.getString(2) ?: ""
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (!isContainerDir(name)) {
                                stack.add(Pair(id, if (rel.isEmpty()) name else "$rel/$name"))
                            }
                        } else {
                            val ext = name.substringAfterLast('.', "").lowercase()
                            val isImage = mime.startsWith("image/") || IMAGE_EXTS.contains(ext)
                            val isPdf = mime == "application/pdf" || ext == "pdf"
                            if (isImage || isPdf) {
                                val relPath = if (rel.isEmpty()) name else "$rel/$name"
                                out.add(Triple(relPath, name, DocumentsContract.buildDocumentUriUsingTree(treeUri, id)))
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
