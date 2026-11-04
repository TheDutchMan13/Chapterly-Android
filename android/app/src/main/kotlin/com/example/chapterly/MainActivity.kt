package com.example.chapterly

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
 *
 * The "chapterly/home" channel feeds the home-screen widget (ChapterlyWidget)
 * and the daily reading reminder (Reminders), asks to show notifications,
 * and passes the widget's play/pause button on to the app.
 * The "chapterly/audio_files" channel picks audiobook files and folders with
 * the system picker, keeps permission to read them (so no storage
 * permission is needed) and reads parts of them for lengths and chapters.
 * It also picks a book file (EPUB or PDF) and copies it into the app's own
 * folder for the reader.
 *
 * The "chapterly/app" channel restarts Chapterly, so it opens with the
 * profile that was just chosen, and hides it from the recent apps and
 * screenshots ("secure") when the app lock asks for that.
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
                        val keep = call.argument<List<String>>("keep") ?: emptyList()
                        // A permission another book (in any profile) still
                        // reads through is kept.
                        val persisted =
                            contentResolver.persistedUriPermissions.map { it.uri }.toSet()
                        val held = keep.mapNotNull { permissionFor(Uri.parse(it), persisted) }.toSet()
                        for (text in uris) {
                            val uri = Uri.parse(text)
                            val permission = permissionFor(uri, persisted)
                            if (permission != null && permission in held) continue
                            release(uri)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        setUpHome(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chapterly/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "uptime") {
                    // Time since the phone was switched on, which changing
                    // the clock does not move (for the PIN waits).
                    result.success(SystemClock.elapsedRealtime())
                    return@setMethodCallHandler
                }
                if (call.method == "secure") {
                    // Blank in the recent apps, and no screenshots.
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method != "restart") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val launch = packageManager.getLaunchIntentForPackage(packageName)
                val component = launch?.component
                if (component == null) {
                    result.error("restart", "No launch activity.", null)
                    return@setMethodCallHandler
                }
                result.success(null)
                // A moment for the reply to reach Dart, then a fresh start.
                main.postDelayed({
                    startActivity(Intent.makeRestartActivityTask(component))
                    Runtime.getRuntime().exit(0)
                }, 200)
            }
    }

    // ---- The home-screen widget and the reading reminder ----

    private val notifyCode = 4104
    private var home: MethodChannel? = null
    private var askingNotifications: MethodChannel.Result? = null

    /** Play/pause on the widget, when it started the app. */
    private var toggleWaiting = false

    private fun setUpHome(engine: FlutterEngine) {
        // The activity's intent is there by now (not yet when it is made).
        // Reopened from recents, the same intent comes back: not a new tap.
        val start = intent
        if (start?.action == ChapterlyWidget.ACTION_TOGGLE &&
            start.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0
        ) {
            toggleWaiting = true
        }
        // Played once: don't let a restart of the activity play it again.
        if (start?.action == ChapterlyWidget.ACTION_TOGGLE) intent = Intent(start).setAction(Intent.ACTION_MAIN)
        home = MethodChannel(engine.dartExecutor.binaryMessenger, "chapterly/home").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        ChapterlyWidget.save(
                            this@MainActivity,
                            call.argument<String>("title") ?: "Chapterly",
                            call.argument<String>("author") ?: "",
                            call.argument<String>("detail") ?: "",
                            call.argument<Boolean>("audio") ?: false,
                            call.argument<Boolean>("playing") ?: false,
                        )
                        result.success(null)
                    }
                    "setReminder" -> {
                        Reminders.save(
                            this@MainActivity,
                            call.argument<Boolean>("on") ?: false,
                            call.argument<Int>("minutes") ?: (20 * 60),
                            call.argument<String>("text"),
                        )
                        result.success(null)
                    }
                    "askNotifications" -> askNotifications(result)
                    "takeToggle" -> {
                        result.success(toggleWaiting)
                        toggleWaiting = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Android 13 and later ask once before an app may notify. */
    private fun askNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (askingNotifications != null) {
            result.success(false)
            return
        }
        askingNotifications = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notifyCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notifyCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        askingNotifications?.success(granted)
        askingNotifications = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ChapterlyWidget.ACTION_TOGGLE) {
            val channel = home
            if (channel != null) channel.invokeMethod("toggle", null) else toggleWaiting = true
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

    /**
     * The kept permission a file is read through: its own, or the one for
     * the folder it was picked with. Null when there is none.
     */
    private fun permissionFor(uri: Uri, held: Set<Uri>): Uri? {
        if (uri in held) return uri
        return try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                val treeId = DocumentsContract.getTreeDocumentId(uri)
                val tree = DocumentsContract.buildTreeDocumentUri(uri.authority, treeId)
                if (tree in held) tree else null
            } else {
                null
            }
        } catch (e: Exception) {
            null
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
