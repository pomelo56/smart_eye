import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/install_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstallService', () {
    const channel = MethodChannel('com.smart_eye/installer');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('canInstall', () {
      test('returns true when platform reports true', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'canRequestPackageInstalls') return true;
          return null;
        });

        final service = InstallService();
        expect(await service.canInstall(), isTrue);
      });

      test('returns false when platform reports false', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'canRequestPackageInstalls') return false;
          return null;
        });

        final service = InstallService();
        expect(await service.canInstall(), isFalse);
      });

      test('returns false when platform returns null', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);

        final service = InstallService();
        expect(await service.canInstall(), isFalse);
      });
    });

    group('openInstallSettings', () {
      test('returns true when settings screen is launched', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'openInstallSettings') return true;
          return null;
        });

        final service = InstallService();
        expect(await service.openInstallSettings(), isTrue);
      });

      test('returns false when settings screen cannot be launched', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'openInstallSettings') return false;
          return null;
        });

        final service = InstallService();
        expect(await service.openInstallSettings(), isFalse);
      });
    });

    group('installApk', () {
      test('returns success when installer is launched', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'installApk') {
            return <String, dynamic>{
              'success': true,
            };
          }
          return null;
        });

        final service = InstallService();
        final result = await service.installApk('/tmp/app.apk');
        expect(result.success, isTrue);
        expect(result.error, isNull);
      });

      test('returns permission_denied when install permission is missing',
          () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'installApk') {
            return <String, dynamic>{
              'success': false,
              'error': 'permission_denied',
            };
          }
          return null;
        });

        final service = InstallService();
        final result = await service.installApk('/tmp/app.apk');
        expect(result.success, isFalse);
        expect(result.error, equals('permission_denied'));
      });

      test('returns file_not_found when the APK does not exist', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'installApk') {
            return <String, dynamic>{
              'success': false,
              'error': 'file_not_found',
            };
          }
          return null;
        });

        final service = InstallService();
        final result = await service.installApk('/tmp/missing.apk');
        expect(result.success, isFalse);
        expect(result.error, equals('file_not_found'));
      });

      test('returns empty_response when platform returns null', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);

        final service = InstallService();
        final result = await service.installApk('/tmp/app.apk');
        expect(result.success, isFalse);
        expect(result.error, equals('empty_response'));
      });

      test('passes the APK path to the platform channel', () async {
        String? capturedPath;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'installApk') {
            capturedPath = (call.arguments as Map<dynamic, dynamic>)['path']
                as String?;
            return <String, dynamic>{'success': true};
          }
          return null;
        });

        final service = InstallService();
        await service.installApk('/tmp/smart_eye.apk');
        expect(capturedPath, equals('/tmp/smart_eye.apk'));
      });
    });
  });
}
