import 'dart:async';

import 'package:flutter/services.dart';

/// Result of an APK install attempt.
class InstallResult {
  /// Creates an [InstallResult].
  const InstallResult({required this.success, this.error});

  /// True when the system installer was successfully launched.
  final bool success;

  /// Error code or message when [success] is false.
  ///
  /// Common values:
  /// - `permission_denied` — the app cannot request package installs.
  /// - `file_not_found` — the downloaded APK does not exist.
  /// - Other platform-specific messages.
  final String? error;

  /// Parses the Map returned by the native installer channel.
  factory InstallResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const InstallResult(success: false, error: 'empty_response');
    }
    return InstallResult(
      success: map['success'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }
}

/// Handles APK install permission and launches the system installer.
class InstallService {
  static const _channel = MethodChannel('com.smart_eye/installer');

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
  /// The caller must ensure [canInstall] returns true before calling this
  /// method, otherwise the result will report `permission_denied`.
  Future<InstallResult> installApk(String path) async {
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'installApk',
      {'path': path},
    );
    return InstallResult.fromMap(map);
  }
}
