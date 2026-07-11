import 'dart:io';

import 'package:dio/dio.dart';

import 'update_service.dart';

/// Downloads the APK from a remote URL to a local file.
///
/// **CVE-STYLE-004:** All download URLs are validated against the trusted
/// domain whitelist before any network request is made.
class DownloadService {
  final Dio _dio;

  /// Creates a [DownloadService].
  ///
  /// The optional [dio] parameter is used in tests.
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  /// Downloads the file at [url] to [savePath].
  ///
  /// The optional [onProgress] callback receives a value between 0.0 and 1.0
  /// whenever the download makes progress. Callers can ignore it or use it
  /// to drive accessibility announcements.
  ///
  /// Throws [ArgumentError] if [url] is not from a trusted domain.
  /// Throws [DioException] on network errors.
  Future<String> downloadApk(
    String url,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    // CVE-STYLE-004: Defense in depth - validate URL again before download
    if (!UpdateService.isValidDownloadUrl(url)) {
      throw ArgumentError('Download URL is not from a trusted domain: $url');
    }

    final file = File(savePath);
    if (file.existsSync()) {
      file.deleteSync();
    }

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    return savePath;
  }
}
