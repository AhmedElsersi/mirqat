package com.mirqat.app

import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the keep-screen-awake channel.
 *
 * Extends audio_service's activity rather than FlutterActivity so that the
 * activity and the media-playback service share one FlutterEngine: the lock
 * screen's pause button has to reach the same Dart isolate the session is
 * running in.
 *
 * A memorization session is long and mostly hands-off, so the screen must not
 * dim mid-recitation. This is a window flag rather than a package, keeping the
 * approved dependency list untouched (CLAUDE.md A.4).
 */
class MainActivity : AudioServiceActivity() {
    private companion object {
        const val CHANNEL = "com.mirqat.app/keep_awake"
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
    }
}
