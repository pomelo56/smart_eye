import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/permission_service.dart';

void main() {
  // The default platform implementation uses a MethodChannel, which requires
  // the Flutter binding to be initialized. Call this once before the first
  // test that touches the default platform.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PermissionService with default platform (no MethodChannel handler)',
      () {
    late PermissionService service;

    setUp(() {
      // Make the MethodChannel throw MissingPluginException (the default
      // for a channel with no handler), so we exercise the catch-all path.
      const channel = MethodChannel('com.smart_eye/permission');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      service = PermissionService();
    });

    test('starts in unknown status (no I/O yet)', () {
      expect(service.cameraStatus, PermissionStatus.unknown);
    });

    test(
        'default platform returns unknown when the MethodChannel has no '
        'handler (e.g. running before MainActivity wired it up)', () async {
      // The implementation catches MissingPluginException and reports
      // unknown. Production code wires the handler in MainActivity.onCreate.
      expect(await service.checkCameraPermission(), PermissionStatus.unknown);
      expect(await service.requestCameraPermission(), PermissionStatus.unknown);
      expect(await service.openAppSettings(), isFalse);
      expect(service.cameraStatus, PermissionStatus.unknown);
    });
  });

  group('PermissionService with fake platform', () {
    late _FakePermissionPlatform platform;
    late PermissionService service;

    setUp(() {
      platform = _FakePermissionPlatform();
      service = PermissionService(platform: platform);
    });

    test('checkCameraPermission returns the current platform status', () async {
      platform.cameraStatus = PermissionStatus.denied;
      expect(await service.checkCameraPermission(), PermissionStatus.denied);
      expect(service.cameraStatus, PermissionStatus.denied);

      platform.cameraStatus = PermissionStatus.granted;
      expect(await service.checkCameraPermission(), PermissionStatus.granted);
      expect(service.cameraStatus, PermissionStatus.granted);
    });

    test(
        'checkCameraPermission reflects permanentlyDenied state from the '
        'platform', () async {
      // Some Android devices report "permanently denied" via the
      // shouldShowRequestPermissionRationale path; the platform layer
      // abstracts that away and we just see permanentlyDenied here.
      platform.cameraStatus = PermissionStatus.permanentlyDenied;
      expect(
        await service.checkCameraPermission(),
        PermissionStatus.permanentlyDenied,
      );
      expect(service.isPermanentlyDenied, isTrue);
    });

    test(
        'requestCameraPermission updates internal status from platform '
        'response', () async {
      platform.cameraStatus = PermissionStatus.permanentlyDenied;
      platform.requestResult = PermissionStatus.granted;

      final result = await service.requestCameraPermission();

      expect(result, PermissionStatus.granted);
      expect(service.cameraStatus, PermissionStatus.granted);
      expect(platform.requestCallCount, 1);
    });

    test('isPermanentlyDenied returns true only for permanentlyDenied',
        () async {
      platform.requestResult = PermissionStatus.permanentlyDenied;
      await service.requestCameraPermission();
      expect(service.isPermanentlyDenied, isTrue);

      platform.requestResult = PermissionStatus.denied;
      await service.requestCameraPermission();
      expect(service.isPermanentlyDenied, isFalse);

      platform.requestResult = PermissionStatus.granted;
      await service.requestCameraPermission();
      expect(service.isPermanentlyDenied, isFalse);
    });

    test('openAppSettings delegates to the platform and returns success',
        () async {
      platform.openSettingsResult = true;
      expect(await service.openAppSettings(), isTrue);
      expect(platform.openSettingsCallCount, 1);

      platform.openSettingsResult = false;
      expect(await service.openAppSettings(), isFalse);
    });
  });
}

/// A test double that replaces the platform-side permission API.
///
/// The real implementation lives in `permission_service_io.dart` and
/// talks to the Android camera plugin / system settings. The test does
/// not need that — it only verifies that [PermissionService] propagates
/// the platform's state correctly.
class _FakePermissionPlatform implements PermissionPlatform {
  PermissionStatus cameraStatus = PermissionStatus.unknown;
  PermissionStatus requestResult = PermissionStatus.granted;
  bool openSettingsResult = true;
  int requestCallCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<PermissionStatus> checkCameraPermission() async => cameraStatus;

  @override
  Future<PermissionStatus> requestCameraPermission() async {
    requestCallCount++;
    cameraStatus = requestResult;
    return requestResult;
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCallCount++;
    return openSettingsResult;
  }
}
