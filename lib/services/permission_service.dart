import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a camera permission check or request.
///
/// Mirrors the semantics of `permission_handler` without taking a dependency
/// on it. We only model the three states the app needs to make a decision:
/// unknown, denied (can ask again), and permanentlyDenied (must go to
/// system settings).
enum PermissionStatus { unknown, granted, denied, permanentlyDenied }

/// Platform interface for permission operations.
///
/// Production code injects [PermissionPlatformAndroid], tests inject a
/// fake. The interface is intentionally narrow: only what the app's
/// permission flow actually needs.
abstract class PermissionPlatform {
  /// Returns the current camera permission status without prompting the
  /// user.
  Future<PermissionStatus> checkCameraPermission();

  /// Triggers the system permission dialog. Returns the user's choice.
  ///
  /// On Android, this maps to the runtime permission request that pops up
  /// the first time the camera is needed.
  Future<PermissionStatus> requestCameraPermission();

  /// Opens the app's page in the system settings app.
  ///
  /// Used as a recovery path when the user has selected "Don't ask again"
  /// and the system dialog will no longer be shown. The app cannot grant
  /// itself permission, so the user must enable it from settings.
  Future<bool> openAppSettings();
}

/// Camera permission service.
///
/// This is the single entry point for everything camera-permission-related
/// in the app. It exposes a synchronous [cameraStatus] for UI/state checks
/// and a small set of async actions ([checkCameraPermission],
/// [requestCameraPermission], [openAppSettings]).
///
/// Design notes:
/// - We do not depend on `permission_handler` to avoid an extra ~2 MB of
///   native code. The `camera` plugin already throws
///   `CameraException(CameraAccessDenied, ...)` when permission is missing,
///   and the Android `PackageManager.checkPermission` API is reachable via
///   a [MethodChannel] without any new dependency.
/// - State is held as a single field rather than a stream so the HomeScreen
///   can read the current status synchronously in `build()`.
class PermissionService {
  PermissionService({PermissionPlatform? platform})
      : _platform = platform ?? _DefaultPermissionPlatform();

  final PermissionPlatform _platform;

  PermissionStatus _status = PermissionStatus.unknown;

  /// The most recent known camera permission status.
  ///
  /// Starts as [PermissionStatus.unknown] and is updated by every call to
  /// [checkCameraPermission] or [requestCameraPermission].
  PermissionStatus get cameraStatus => _status;

  /// True if the user has previously selected "Don't ask again" (or has
  /// revoked the permission from settings). In this state, calling
  /// [requestCameraPermission] will no longer show the system dialog — the
  /// user must be guided to system settings instead.
  bool get isPermanentlyDenied => _status == PermissionStatus.permanentlyDenied;

  /// Refreshes [cameraStatus] from the platform without prompting the user.
  Future<PermissionStatus> checkCameraPermission() {
    return _platform.checkCameraPermission().then((s) {
      _status = s;
      return s;
    });
  }

  /// Prompts the user for camera permission.
  ///
  /// The system dialog is shown only on the first invocation. If the user
  /// has previously denied and selected "Don't ask again", the dialog will
  /// not appear and the result will be [PermissionStatus.permanentlyDenied].
  /// In that case the caller should route to [openAppSettings] instead of
  /// retrying.
  Future<PermissionStatus> requestCameraPermission() {
    return _platform.requestCameraPermission().then((s) {
      _status = s;
      return s;
    });
  }

  /// Opens the app's settings page so the user can manually enable
  /// camera access.
  ///
  /// Returns true if the settings app was successfully launched. Returns
  /// false if the platform could not start it (very rare — only happens
  /// on a broken system).
  Future<bool> openAppSettings() => _platform.openAppSettings();
}

/// Default [PermissionPlatform] implementation that talks to Android via
/// the [MethodChannel] exposed by `MainActivity`.
///
/// We intentionally re-use the existing `com.smart_eye/audio` host
/// activity rather than introducing a new one. The activity is already
/// guaranteed to be alive when permission checks run, and the channel
/// is already declared in `proguard-rules.pro` for MainActivity, so R8
/// will not strip the handler.
class _DefaultPermissionPlatform implements PermissionPlatform {
  static const _channel = MethodChannel('com.smart_eye/permission');

  @override
  Future<PermissionStatus> checkCameraPermission() async {
    try {
      final raw = await _channel.invokeMethod<String>('checkCamera');
      return _parseStatus(raw);
    } on MissingPluginException catch (e) {
      // Channel not wired up (e.g. running in a unit test that didn't
      // mock the platform). Treat as unknown so the caller can decide
      // how to proceed — usually by attempting to use the camera and
      // catching the resulting CameraException.
      debugPrint('[Permission] checkCamera: channel not available: $e');
      return PermissionStatus.unknown;
    } on PlatformException catch (e) {
      debugPrint('[Permission] checkCamera: platform error: $e');
      return PermissionStatus.unknown;
    }
  }

  @override
  Future<PermissionStatus> requestCameraPermission() async {
    try {
      final raw = await _channel.invokeMethod<String>('requestCamera');
      return _parseStatus(raw);
    } on MissingPluginException catch (e) {
      debugPrint('[Permission] requestCamera: channel not available: $e');
      return PermissionStatus.unknown;
    } on PlatformException catch (e) {
      debugPrint('[Permission] requestCamera: platform error: $e');
      return PermissionStatus.unknown;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openAppSettings');
      return ok ?? false;
    } on MissingPluginException catch (e) {
      debugPrint('[Permission] openAppSettings: channel not available: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[Permission] openAppSettings: platform error: $e');
      return false;
    }
  }

  static PermissionStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'granted':
        return PermissionStatus.granted;
      case 'denied':
        return PermissionStatus.denied;
      case 'permanently_denied':
      case 'permanentlyDenied':
        return PermissionStatus.permanentlyDenied;
      default:
        return PermissionStatus.unknown;
    }
  }
}
