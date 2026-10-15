package com.mirqat.app

import android.content.Intent
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the keep-screen-awake and share channels.
 *
 * Extends audio_service's activity rather than FlutterActivity so that the
 * activity and the media-playback service share one FlutterEngine: the lock
 * screen's pause button has to reach the same Dart isolate the session is
 * running in.
 *
 * A memorization session is long and mostly hands-off, so the screen must not
 * dim mid-recitation. This is a window flag rather than a package, keeping the
 * approved dependency list untouched (CLAUDE.md A.4). Sharing is ACTION_SEND
 * over a FileProvider URI, for the same reason.
 */
class MainActivity : AudioServiceActivity() {
    private companion object {
        const val CHANNEL = "com.mirqat.app/keep_awake"
        const val SHARE_CHANNEL = "com.mirqat.app/share"
    }

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
    }
}
