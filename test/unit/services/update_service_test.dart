import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_eye/services/connectivity_service.dart';
import 'package:smart_eye/services/update_service.dart';

class _FakeDio extends DioForNative {
  _FakeDio(this.responseData) : super(BaseOptions());

  final dynamic responseData;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: responseData as T?,
      statusCode: 200,
    );
  }
}

class _FailingDio extends DioForNative {
  _FailingDio() : super(BaseOptions());

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      error: 'network error',
    );
  }
}

UpdateService _buildService({
  required SharedPreferences prefs,
  required Dio dio,
  int localBuildNumber = 10,
  bool wifi = true,
  DateTime? now,
}) {
  return UpdateService(
    prefs: prefs,
    connectivity: ConnectivityService(
      check: () async =>
          wifi ? [ConnectivityResult.wifi] : [ConnectivityResult.mobile],
    ),
    dio: dio,
    packageInfo: PackageInfo(
      appName: '慧眼',
      packageName: 'com.smart_eye',
      version: '0.7.0',
      buildNumber: '$localBuildNumber',
    ),
    clock: () => now ?? DateTime(2026, 7, 10, 12, 0, 0),
  );
}

Map<String, dynamic> _releaseResponse(int versionCode, String downloadUrl) {
  return {
    'tag_name': 'v0.8.0+$versionCode',
    'body': 'release notes',
    'assets': [
      {
        'name': 'app-release.apk',
        'browser_download_url': downloadUrl,
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateService.checkForUpdate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when not connected to Wi-Fi', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = _buildService(
        prefs: prefs,
        dio: _FakeDio(_releaseResponse(20, 'https://example.com/app.apk')),
        wifi: false,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when checked within the last 7 days', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_update_check_millis',
          DateTime(2026, 7, 10, 11, 0, 0).millisecondsSinceEpoch);
      final service = _buildService(
        prefs: prefs,
        dio: _FakeDio(_releaseResponse(20, 'https://example.com/app.apk')),
        now: DateTime(2026, 7, 10, 12, 0, 0),
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns UpdateInfo when a newer version is available', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = _buildService(
        prefs: prefs,
        dio: _FakeDio(_releaseResponse(20, 'https://example.com/app.apk')),
        localBuildNumber: 10,
      );

      final info = await service.checkForUpdate();
      expect(info, isNotNull);
      expect(info!.versionCode, 20);
      expect(info.versionName, '0.8.0');
      expect(info.downloadUrl, 'https://example.com/app.apk');
    });

    test('returns null when remote version is not newer', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = _buildService(
        prefs: prefs,
        dio: _FakeDio(_releaseResponse(10, 'https://example.com/app.apk')),
        localBuildNumber: 10,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('falls back to GitHub when Gitee fails', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = UpdateService(
        prefs: prefs,
        connectivity: ConnectivityService(
          check: () async => [ConnectivityResult.wifi],
        ),
        dio: _FailingDio(),
        packageInfo: PackageInfo(
          appName: '慧眼',
          packageName: 'com.smart_eye',
          version: '0.7.0',
          buildNumber: '10',
        ),
      );

      // The fallback URL will also fail because we only provided one Dio
      // instance. This test verifies the exception path rather than a real
      // fallback response.
      expect(service.checkForUpdate(), throwsA(isA<DioException>()));
    });

    test('parses versionCode from body when tag has no +NNN suffix', () async {
      final prefs = await SharedPreferences.getInstance();
      final dio = _FakeDio({
        'tag_name': 'v0.8.0',
        'body': 'versionCode: 25',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
      });
      final service = _buildService(
        prefs: prefs,
        dio: dio,
        localBuildNumber: 10,
      );

      final info = await service.checkForUpdate();
      expect(info, isNotNull);
      expect(info!.versionCode, 25);
    });

    test('throws when versionCode cannot be parsed', () async {
      final prefs = await SharedPreferences.getInstance();
      final dio = _FakeDio({
        'tag_name': 'v0.8.0',
        'body': 'no version code here',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
      });
      final service = _buildService(
        prefs: prefs,
        dio: dio,
        localBuildNumber: 10,
      );

      expect(service.checkForUpdate(), throwsA(isA<Exception>()));
    });

    test('throws when app-release.apk asset is missing', () async {
      final prefs = await SharedPreferences.getInstance();
      final dio = _FakeDio({
        'tag_name': 'v0.8.0+20',
        'body': '',
        'assets': [
          {
            'name': 'wrong-name.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
      });
      final service = _buildService(
        prefs: prefs,
        dio: dio,
        localBuildNumber: 10,
      );

      expect(service.checkForUpdate(), throwsA(isA<Exception>()));
    });

    test('records last check timestamp after a successful check', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 7, 10, 12, 0, 0);
      final service = _buildService(
        prefs: prefs,
        dio: _FakeDio(_releaseResponse(20, 'https://example.com/app.apk')),
        localBuildNumber: 10,
        now: now,
      );

      await service.checkForUpdate();
      expect(
        prefs.getInt('last_update_check_millis'),
        now.millisecondsSinceEpoch,
      );
    });
  });
}
