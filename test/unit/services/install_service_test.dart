import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/apk_verifier.dart';
import 'package:smart_eye/services/install_service.dart';

/// Fake ApkVerifier that always returns trusted for testing.
class FakeTrustedApkVerifier implements ApkVerifier {
  @override
  Future<bool> isApkTrusted(String apkPath) async => true;
}

/// Fake ApkVerifier that always returns untrusted (signature mismatch).
class FakeUntrustedApkVerifier implements ApkVerifier {
  @override
  Future<bool> isApkTrusted(String apkPath) async => false;
}

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

        final service = InstallService(verifier: FakeTrustedApkVerifier());
        expect(await service.canInstall(), isTrue);
      });

      test('returns false when platform reports false', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'canRequestPackageInstalls') return false;
          return null;
        });

        final service = InstallService(verifier: FakeTrustedApkVerifier());
        expect(await service.canInstall(), isFalse);
      });

      test('returns false when platform returns null', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);

        final service = InstallService(verifier: FakeTrustedApkVerifier());
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

        final service = InstallService(verifier: FakeTrustedApkVerifier());
        expect(await service.openInstallSettings(), isTrue);
      });

      test('returns false when settings screen cannot be launched', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'openInstallSettings') return false;
          return null;
        });

        final service = InstallService(verifier: FakeTrustedApkVerifier());
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

        final service = InstallService(verifier: FakeTrustedApkVerifier());
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

        final service = InstallService(verifier: FakeTrustedApkVerifier());
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

        final service = InstallService(verifier: FakeTrustedApkVerifier());
        final result = await service.installApk('/tmp/missing.apk');
        expect(result.success, isFalse);
        expect(result.error, equals('file_not_found'));
      });

      test('returns empty_response when platform returns null', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);

        final service = InstallService(verifier: FakeTrustedApkVerifier());
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

        final service = InstallService(verifier: FakeTrustedApkVerifier());
        await service.installApk('/tmp/smart_eye.apk');
        expect(capturedPath, equals('/tmp/smart_eye.apk'));
      });

      test('returns signature_mismatch when APK verification fails (CVE-STYLE-001)', () async {
        // 即使平台installer返回成功，签名校验失败也应该阻止安装
        bool installerCalled = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'installApk') {
            installerCalled = true;
            return <String, dynamic>{'success': true};
          }
          return null;
        });

        final service = InstallService(verifier: FakeUntrustedApkVerifier());
        final result = await service.installApk('/tmp/app.apk');
        expect(result.success, isFalse);
        expect(result.error, equals('signature_mismatch'));
        expect(result.message, contains('签名'));
        expect(installerCalled, isFalse, reason: '安装器不应被调用');
      });

      test('returns signature_mismatch for empty path', () async {
        final service = InstallService(verifier: FakeUntrustedApkVerifier());
        final result = await service.installApk('');
        expect(result.success, isFalse);
        expect(result.error, equals('signature_mismatch'));
      });
    });
  });
}
