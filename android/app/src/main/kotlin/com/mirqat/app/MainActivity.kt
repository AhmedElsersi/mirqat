package com.mirqat.app

import android.app.Activity
import android.content.Intent
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/**
 * Hosts the keep-screen-awake, share and file-picking channels.
 *
 * Extends audio_service's activity rather than FlutterActivity so that the
 * activity and the media-playback service share one FlutterEngine: the lock
 * screen's pause button has to reach the same Dart isolate the session is
 * running in.
 *
 * A memorization session is long and mostly hands-off, so the screen must not
 * dim mid-recitation. This is a window flag rather than a package, keeping the
 * approved dependency list untouched (CLAUDE.md A.4). Sharing is ACTION_SEND
 * over a FileProvider URI, for the same reason, and picking a file is
 * ACTION_OPEN_DOCUMENT — the system's own picker, which reaches Downloads,
 * Drive and whatever else the device offers, with no storage permission.
 */
class MainActivity : AudioServiceActivity() {
    private companion object {
        const val CHANNEL = "com.mirqat.app/keep_awake"
        const val SHARE_CHANNEL = "com.mirqat.app/share"
        const val FILES_CHANNEL = "com.mirqat.app/files"
        const val PICK_TEXT = 4711

        /** A backup is a few hundred kilobytes; anything near this is not one. */
        const val MAX_TEXT_BYTES = 16 * 1024 * 1024
    }

    /** The Dart call waiting on the picker, answered in onActivityResult. */
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepAwake" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                )
                            } else {
                                window.clearFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                )
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareFile" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val path = arguments?.get("path") as? String
                        val mimeType =
                            arguments?.get("mimeType") as? String ?: "image/png"
                        val text = arguments?.get("text") as? String
                        if (path == null) {
                            result.error(
                                "bad_arguments",
                                "shareFile needs a \"path\".",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("not_found", "No file at $path.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            // The authority matches the manifest's share
                            // FileProvider, which exposes only the cache dir's
                            // share/ folder — exactly where Dart writes.
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.share",
                                file
                            )
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = mimeType
                                putExtra(Intent.EXTRA_STREAM, uri)
                                if (text != null) {
                                    putExtra(Intent.EXTRA_TEXT, text)
                                }
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(send, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickText" -> {
                        if (pendingPick != null) {
                            result.error("busy", "A file is already being chosen.", null)
                            return@setMethodCallHandler
                        }
                        val open = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // A backup sent through a chat app often arrives
                            // typed as anything but JSON; the file's own
                            // contents decide, in Dart.
                            type = "*/*"
                        }
                        pendingPick = result
                        try {
                            startActivityForResult(open, PICK_TEXT)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("no_picker", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("FlutterActivity is not a ComponentActivity; this is its API.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_TEXT) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Cancelled: an answer, not a failure.
            result.success(null)
            return
        }
        // Read off the main thread: the file may be on a network drive.
        Thread {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    var total = 0
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > MAX_TEXT_BYTES) throw IOException("File too large.")
                        out.write(buffer, 0, n)
                    }
                    out.toByteArray()
                } ?: throw IOException("The file could not be opened.")
                val text = String(bytes, Charsets.UTF_8)
                runOnUiThread { result.success(text) }
            } catch (e: Exception) {
                runOnUiThread { result.error("unreadable", e.message, null) }
            }
        }.start()
    }
}
