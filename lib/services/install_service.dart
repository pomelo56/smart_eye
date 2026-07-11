import 'dart:async';

import 'package:flutter/services.dart';

import 'apk_verifier.dart';

/// Result of an APK install attempt.
class InstallResult {
  /// Creates an [InstallResult].
  const InstallResult({required this.success, this.error, this.message});

  /// True when the system installer was successfully launched.
  final bool success;

  /// Error code or message when [success] is false.
  ///
  /// Common values:
  /// - `permission_denied` — the app cannot request package installs.
  /// - `file_not_found` — the downloaded APK does not exist.
  /// - `signature_mismatch` — APK signature does not match the current app (CVE-STYLE-001).
  /// - Other platform-specific messages.
  final String? error;

  /// Optional human-readable error message for TTS feedback.
  final String? message;

  /// Parses the Map returned by the native installer channel.
  factory InstallResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const InstallResult(success: false, error: 'empty_response');
    }
    return InstallResult(
      success: map['success'] as bool? ?? false,
      error: map['error'] as String?,
      message: map['message'] as String?,
    );
  }
}

/// Handles APK install permission and launches the system installer.
///
/// CVE-STYLE-001: Before launching the installer, verifies that the APK's
/// signature matches the current app's signature to prevent supply-chain attacks.
class InstallService {
  static const _channel = MethodChannel('com.smart_eye/installer');
  final ApkVerifier _verifier;

  /// Creates an [InstallService] with an optional [ApkVerifier].
  InstallService({ApkVerifier? verifier})
      : _verifier = verifier ?? ApkVerifier();

  /// Returns whether the app is allowed to request package installs.
  ///
  /// On Android 8.0+ this reflects the `REQUEST_INSTALL_PACKAGES` setting;
  /// older versions return true.
  Future<bool> canInstall() async {
    final ok = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
    return ok ?? false;
  }

  /// Opens the system screen where the user can allow installs from this app.
  ///
  /// Returns true if the settings screen was launched.
  Future<bool> openInstallSettings() async {
    final ok = await _channel.invokeMethod<bool>('openInstallSettings');
    return ok ?? false;
  }

  /// Launches the system installer for the APK at [path].
  ///
  /// **CVE-STYLE-001:** Before installing, this method verifies that the APK's
  /// signature matches the current app. If the signature does not match
  /// (indicating the APK has been tampered with or replaced by an attacker),
  /// installation is aborted and `signature_mismatch` error is returned.
  ///
  /// The caller must ensure [canInstall] returns true before calling this
  /// method, otherwise the result will report `permission_denied`.
  Future<InstallResult> installApk(String path) async {
    // CVE-STYLE-001: 首先验证APK签名，防止恶意APK安装
    final isTrusted = await _verifier.isApkTrusted(path);
    if (!isTrusted) {
      return const InstallResult(
        success: false,
        error: 'signature_mismatch',
        message: 'APK签名验证失败，安装已终止以保障安全',
      );
    }

    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'installApk',
      {'path': path},
    );
    return InstallResult.fromMap(map);
  }
}
