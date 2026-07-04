package com.example.smart_eye

import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * MainActivity exposes a small MethodChannel to play bundled audio assets.
 *
 * This is the fallback voice strategy for OPPO/ColorOS devices where the
 * system's TextToSpeech engine is visible in Settings but cannot be bound by
 * third-party apps.  All speech prompts are pre-recorded and shipped as assets.
 */
class MainActivity : FlutterActivity() {
    private val channel = "com.smart_eye/audio"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isPlaying = AtomicBoolean(false)

    /// Reference to the currently active MediaPlayer, so stop() can truly halt
    /// playback instead of just flipping a flag.
    @Volatile
    private var currentPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAssets" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val volume = (call.argument<Number>("volume")?.toFloat() ?: 1.0f)
                        .coerceIn(0.0f, 1.0f)
                    playAssets(paths, volume, result)
                }
                "stop" -> {
                    stopPlayback()
                    result.success(true)
                }
                "isPlaying" -> {
                    result.success(isPlaying.get())
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Plays a list of asset audio files sequentially.
     *
     * Each path is relative to the Flutter assets root, e.g. "assets/audio/num_1.mp3".
     * The [result] is returned immediately with success=true; completion is not awaited.
     */
    private fun playAssets(paths: List<String>, volume: Float, result: MethodChannel.Result) {
        if (paths.isEmpty()) {
            result.success(true)
            return
        }

        mainHandler.post {
            stopPlayback()
            isPlaying.set(true)
            playNext(paths, 0, volume)
            result.success(true)
        }
    }

    private fun playNext(paths: List<String>, index: Int, volume: Float) {
        if (index >= paths.size) {
            isPlaying.set(false)
            currentPlayer = null
            return
        }

        val path = paths[index]
        val player = MediaPlayer()
        var afd: AssetFileDescriptor? = null

        try {
            // Flutter assets are packaged under assets/flutter_assets/ in the APK.
            // The Dart side sends the asset key (e.g. "assets/audio/num_1.mp3"),
            // so we need to prepend the flutter_assets prefix for AssetManager.
            afd = assets.openFd("flutter_assets/$path")
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            player.setVolume(volume, volume)
            // Play at 2.0x speed for faster voice feedback.
            player.playbackParams = player.playbackParams.apply {
                speed = 2.0f
            }
            player.setOnCompletionListener {
                it.release()
                afd?.close()
                // Clear reference before advancing to next clip.
                if (currentPlayer === it) {
                    currentPlayer = null
                }
                playNext(paths, index + 1, volume)
            }
            player.setOnErrorListener { mp, what, extra ->
                android.util.Log.e("SmartEye", "MediaPlayer error: what=$what extra=$extra for $path")
                mp.release()
                afd?.close()
                if (currentPlayer === mp) {
                    currentPlayer = null
                }
                // Try to continue with the next clip.
                playNext(paths, index + 1, volume)
                true
            }
            player.prepare()
            // Track the active player so stop() can truly halt it.
            currentPlayer = player
            player.start()
        } catch (e: Exception) {
            android.util.Log.e("SmartEye", "Failed to play asset $path: ${e.message}")
            afd?.close()
            player.release()
            if (currentPlayer === player) {
                currentPlayer = null
            }
            playNext(paths, index + 1, volume)
        }
    }

    /// Truly stops and releases the active MediaPlayer.
    /// Previous implementation only flipped a flag, which caused audio overlap
    /// when a new speak() call started before the old clip finished.
    private fun stopPlayback() {
        isPlaying.set(false)
        currentPlayer?.let { p ->
            try {
                if (p.isPlaying) {
                    p.stop()
                }
                p.release()
            } catch (e: Exception) {
                android.util.Log.e("SmartEye", "stopPlayback error: ${e.message}")
            }
            currentPlayer = null
        }
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }
}
