package com.example.chapterly

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * AudioServiceActivity lets audiobooks keep playing with the screen off.
 * The "chapterly/audio_files" channel picks audiobook files and folders with
 * the system picker, keeps permission to read them (so no storage
 * permission is needed) and reads parts of them for lengths and chapters.
 * It also picks a book file (EPUB or PDF) and copies it into the app's own
 * folder for the reader.
 *
 * The "chapterly/reader" channel keeps the screen on, sets the brightness
 * and turns the volume buttons into page turns while the reader is open.
 */
class MainActivity : AudioServiceActivity() {
    private val pickFileCode = 4101
    private val pickFolderCode = 4102
    private val pickBookCode = 4103
    private var pending: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var reader: MethodChannel? = null
    private var volumeKeys = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reader = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chapterly/reader")
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "keepScreenOn" -> {
                            if (call.arguments == true) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(null)
                        }
                        "brightness" -> {
                            // A number from 0 to 1, or null for the phone's own.
                            val value = (call.arguments as? Number)?.toFloat()
                            val attributes = window.attributes
                            attributes.screenBrightness = value?.coerceIn(0.01f, 1f)
                                ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = attributes
                            result.success(null)
                        }
                        "volumeKeys" -> {
                            volumeKeys = call.arguments == true
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chapterly/audio_files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // .m4b files are often not marked as audio.
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf("audio/*", "video/mp4", "application/octet-stream"),
                            )
                            addFlags(readFlags)
                        }
                        startPicker(result, intent, pickFileCode)
                    }
                    "pickBook" -> {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // Some file managers do not mark .epub files.
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf(
                                    "application/epub+zip",
                                    "application/pdf",
                                    "application/octet-stream",
                                ),
                            )
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startPicker(result, intent, pickBookCode)
                    }
                    "copyTo" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        val path = call.argument<String>("path") ?: ""
                        background(result) { copyTo(uri, path) }
                    }
                    "pickFolder" -> {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(readFlags)
                        }
                        startPicker(result, intent, pickFolderCode)
                    }
                    "size" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        background(result) { sizeOf(uri) }
                    }
                    "read" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        val offset = call.argument<Number>("offset")?.toLong() ?: 0L
                        val count = call.argument<Number>("count")?.toInt() ?: 0
                        background(result) { read(uri, offset, count) }
                    }
                    "release" -> {
                        val uris = call.argument<List<String>>("uris") ?: emptyList()
                        for (text in uris) release(Uri.parse(text))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** While the reader asks for it, the volume buttons turn pages. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        if (volumeKeys &&
            (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val direction = if (code == KeyEvent.KEYCODE_VOLUME_DOWN) "next" else "previous"
                reader?.invokeMethod("volumeKey", direction)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private val readFlags =
        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION

    private fun startPicker(result: MethodChannel.Result, intent: Intent, code: Int) {
        if (pending != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        pending = result
        try {
            startActivityForResult(intent, code)
        } catch (e: Exception) {
            pending = null
            result.error("no_picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFileCode &&
            requestCode != pickFolderCode &&
            requestCode != pickBookCode
        ) {
            return
        }
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        if (requestCode == pickBookCode) {
            // Copied right away, so it needs no lasting permission.
            result.success(listOf(mapOf("location" to uri.toString(), "name" to nameOf(uri))))
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            // Still readable for now; it may need picking again after a restart.
        }
        if (requestCode == pickFileCode) {
            result.success(listOf(mapOf("location" to uri.toString(), "name" to nameOf(uri))))
        } else {
            background(result) { listFolder(uri) }
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("audio_files", e.message, null) }
            }
        }
    }

    private fun nameOf(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrEmpty()) return name
                }
            }
        return uri.lastPathSegment ?: "Audio"
    }

    /** Every file in the folder and its subfolders, with the subfolder in the name. */
    private fun listFolder(tree: Uri): List<Map<String, String>> {
        val files = mutableListOf<Map<String, String>>()
        fun walk(documentId: String, prefix: String, depth: Int) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
            val columns = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            contentResolver.query(children, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    val mime = cursor.getString(2) ?: ""
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth < 3) walk(id, "$prefix$name/", depth + 1)
                    } else {
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        files.add(mapOf("location" to uri.toString(), "name" to "$prefix$name"))
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), "", 0)
        return files
    }

    private fun sizeOf(uri: Uri): Long {
        contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
            if (descriptor.statSize >= 0) return descriptor.statSize
        }
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getLong(0)
        }
        return 0L
    }

    private fun read(uri: Uri, offset: Long, count: Int): ByteArray {
        if (count <= 0) return ByteArray(0)
        val descriptor = contentResolver.openFileDescriptor(uri, "r")
            ?: throw IllegalStateException("Cannot open the file.")
        return descriptor.use { file ->
            FileInputStream(file.fileDescriptor).channel.use { channel ->
                val buffer = ByteBuffer.allocate(count)
                channel.position(offset)
                while (buffer.hasRemaining()) {
                    if (channel.read(buffer) <= 0) break
                }
                buffer.array().copyOf(buffer.position())
            }
        }
    }

    /** Copies a picked file to [path] in the app's folder. Returns its size. */
    private fun copyTo(uri: Uri, path: String): Long {
        if (path.isEmpty()) throw IllegalArgumentException("No place to copy to.")
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Cannot open the file.")
        val target = File(path)
        target.parentFile?.mkdirs()
        return input.use { source ->
            target.outputStream().use { output -> source.copyTo(output) }
        }
    }

    /** Lets go of the permission to read a file, or the folder it came from. */
    private fun release(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        try {
            contentResolver.releasePersistableUriPermission(uri, flags)
            return
        } catch (e: Exception) {
            // Not a file picked on its own; try the folder.
        }
        try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                val treeId = DocumentsContract.getTreeDocumentId(uri)
                val tree = DocumentsContract.buildTreeDocumentUri(uri.authority, treeId)
                contentResolver.releasePersistableUriPermission(tree, flags)
            }
        } catch (e: Exception) {
            // Already released.
        }
    }
}
