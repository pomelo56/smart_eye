package com.smart_eye

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * MainActivity exposes three MethodChannels:
 *  - `com.smart_eye/audio` — plays bundled audio assets (see ADR-001).
 *  - `com.smart_eye/permission` — handles camera permission checks,
 *    runtime requests, and opening the app's settings page.
 *  - `com.smart_eye/installer` — handles APK install permission and
 *    launching the system package installer for in-app updates.
 *
 * The voice strategy is pre-recorded audio rather than the system TTS
 * engine, because OPPO/ColorOS devices make the TTS engine visible in
 * Settings but un-bindable by third-party Flutter apps.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.smart_eye/audio"
    private val permissionChannelName = "com.smart_eye/permission"
    private val installerChannelName = "com.smart_eye/installer"
    private val verifierChannelName = "com.smart_eye/apk_verifier"
    private val cameraPermissionRequestCode = 4242

    /// File in [Context.getNoBackupFilesDir] that records whether we have
    /// ever asked the user for camera permission. We intentionally avoid
    /// SharedPreferences / allowBackup so that uninstalling the app always
    /// resets this flag. Otherwise Android/Google/ColorOS backup can restore
    /// the old flag on a fresh install and make the first launch look like
    /// a permanent denial.
    private val cameraRequestedFlagFile by lazy {
        File(noBackupFilesDir, "camera_permission_requested")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val isPlaying = AtomicBoolean(false)
    private lateinit var methodChannel: MethodChannel
    private lateinit var permissionChannel: MethodChannel
    private lateinit var installerChannel: MethodChannel

    /// Pending result for the camera permission request, if the user is
    /// currently being prompted. Set in [requestCameraPermission] and
    /// resolved in [onRequestPermissionsResult].
    private var pendingCameraResult: MethodChannel.Result? = null

    /// Reference to the currently active MediaPlayer, so stop() can truly halt
    /// playback instead of just flipping a flag.
    @Volatile
    private var currentPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> {
                    result.success(true)
                }
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

        // Permission channel — added in v0.7.1 to fix the silent startup
        // failure when the user has not granted camera access.
        permissionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            permissionChannelName
        )
        permissionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkCamera" -> {
                    result.success(currentCameraPermissionStatus())
                }
                "requestCamera" -> {
                    requestCameraPermission(result)
                }
                "openAppSettings" -> {
                    result.success(openAppSettings())
                }
                else -> result.notImplemented()
            }
        }

        // Installer channel — added in v0.8.0 for in-app update.
        installerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installerChannelName
        )
        installerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }
                "openInstallSettings" -> {
                    result.success(openInstallSettings())
                }
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    installApk(path, result)
                }
                else -> result.notImplemented()
            }
        }

        // APK Verifier channel - CVE-STYLE-001: 防止恶意APK安装
        val verifierChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            verifierChannelName
        )
        verifierChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "verifyApkSignature" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(verifyApkSignature(path))
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
            // Notify Dart side that all clips have finished playing.
            methodChannel.invokeMethod("onPlaybackComplete", null)
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

    // ============================================================
    // Camera permission handling (v0.7.1)
    // ============================================================

    /**
     * Returns the current camera permission status as a string compatible
     * with the Dart-side [PermissionStatus] enum.
     *
     * Values: "granted", "denied", "permanently_denied".
     *
     * The "permanently denied" case requires two conditions to both hold:
     * 1. The runtime check returns PERMISSION_DENIED.
     * 2. We have previously asked the user for the permission at least
     *    once (tracked in [cameraRequestedFlagFile]), AND
     *    `shouldShowRequestPermissionRationale` returns false.
     *
     * On a fresh install, before we have ever asked the user,
     * `shouldShowRequestPermissionRationale` also returns false. Without
     * the persistent "has been requested" flag we would incorrectly
     * classify every first launch as permanently denied and jump straight
     * to the system settings page without ever showing the system
     * permission dialog.
     *
     * We store the flag in [Context.getNoBackupFilesDir] instead of
     * SharedPreferences so that uninstalling the app always resets it.
     * Some OEM backups (ColorOS, Google) restore SharedPreferences even
     * when `allowBackup="false"` is set, which caused fresh installs to
     * be misclassified as permanently denied.
     */
    private fun currentCameraPermissionStatus(): String {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return "granted"

        val hasRequestedBefore = cameraRequestedFlagFile.exists()
        if (!hasRequestedBefore) {
            // Never asked the user yet — the system dialog can still be shown.
            return "denied"
        }

        val rationale = ActivityCompat.shouldShowRequestPermissionRationale(
            this, Manifest.permission.CAMERA
        )
        // If rationale is false AND we have asked before, the user selected
        // "Don't ask again". The system dialog will not appear; the only
        // recovery path is the settings page.
        return if (rationale) "denied" else "permanently_denied"
    }

    /**
     * Triggers the system permission dialog for the camera.
     *
     * If the dialog cannot be shown (e.g. permanently denied), the
     * result is returned synchronously. Otherwise, [pendingCameraResult]
     * is held and the final result is delivered in
     * [onRequestPermissionsResult].
     */
    private fun requestCameraPermission(result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success("granted")
            return
        }

        if (pendingCameraResult != null) {
            // A request is already in flight; tell Dart to wait rather
            // than than firing a second dialog and losing track of the
            // first result.
            result.success("denied")
            return
        }

        // Record that we have asked the user at least once, so future
        // checks can distinguish "never asked" from "permanently denied".
        try {
            cameraRequestedFlagFile.createNewFile()
        } catch (e: Exception) {
            android.util.Log.w("SmartEye", "无法创建权限请求标志文件", e)
        }

        pendingCameraResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            cameraPermissionRequestCode
        )
    }

    /**
     * Opens the app's settings page so the user can manually grant the
     * camera permission.
     *
     * Returns true if the settings activity was launched; false if the
     * platform refused to start it.
     */
    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.fromParts("package", packageName, null)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.e("SmartEye", "openAppSettings failed: ${e.message}")
            false
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != cameraPermissionRequestCode) return

        val pending = pendingCameraResult ?: return
        pendingCameraResult = null

        // Re-evaluate using the same logic as the synchronous check so
        // the Dart side sees a consistent state.
        pending.success(currentCameraPermissionStatus())
    }

    // ============================================================
    // APK installer handling (v0.8.0)
    // ============================================================

    /**
     * Returns whether the app is allowed to request package installs.
     *
     * On Android 8.0+ this checks [PackageManager.canRequestPackageInstalls].
     * On older versions we assume true because there is no equivalent API.
     */
    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /**
     * Opens the system screen where the user can allow installs from this app.
     *
     * This is required on Android 8.0+ when [canRequestPackageInstalls] returns
     * false. The user must toggle the setting and return to the app.
     */
    private fun openInstallSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.e("SmartEye", "openInstallSettings failed: ${e.message}")
            false
        }
    }

    /**
     * Launches the system package installer for the APK at [path].
     *
     * The file is exposed through a [FileProvider] so the installer can read
     * it without requiring broad storage permissions. If the app does not yet
     * have install permission, the result reports "permission_denied" and the
     * caller should guide the user to [openInstallSettings].
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        if (!canRequestPackageInstalls()) {
            result.success(mapOf("success" to false, "error" to "permission_denied"))
            return
        }

        val file = File(path)
        if (!file.exists()) {
            result.success(mapOf("success" to false, "error" to "file_not_found"))
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            android.util.Log.e("SmartEye", "installApk failed: ${e.message}")
            result.success(mapOf("success" to false, "error" to (e.message ?: "unknown")))
        }
    }

    /**
     * CVE-STYLE-001: 验证APK文件签名是否与当前应用签名一致。
     * 这是防止供应链攻击的关键防护：即使下载了恶意APK，
     * 由于签名不匹配，也不会被安装。
     */
    private fun verifyApkSignature(apkPath: String): Boolean {
        if (apkPath.isEmpty()) return false
        val apkFile = File(apkPath)
        if (!apkFile.exists()) return false

        return try {
            // 获取下载APK的包信息和签名
            val apkFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNATURES.toLong())
            } else {
                null
            }

            @Suppress("DEPRECATION")
            val apkInfo = if (apkFlags != null) {
                packageManager.getPackageArchiveInfo(apkPath, apkFlags)
            } else {
                packageManager.getPackageArchiveInfo(apkPath, PackageManager.GET_SIGNATURES)
            } ?: return false

            // 获取当前应用的签名
            val currentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNATURES.toLong())
            } else {
                null
            }

            @Suppress("DEPRECATION")
            val currentInfo = if (currentFlags != null) {
                packageManager.getPackageInfo(packageName, currentFlags)
            } else {
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            } ?: return false

            // 比对签名
            @Suppress("DEPRECATION")
            val apkSigs = apkInfo.signatures ?: return false
            @Suppress("DEPRECATION")
            val currentSigs = currentInfo.signatures ?: return false

            if (apkSigs.size != currentSigs.size) return false

            currentSigs.all { currentSig ->
                apkSigs.any { apkSig ->
                    currentSig.toCharsString() == apkSig.toCharsString()
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("SmartEye", "APK签名验证失败: ${e.message}")
            false
        }
    }
}
