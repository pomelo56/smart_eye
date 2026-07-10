import 'dart:io';

import 'package:dio/dio.dart';

/// Downloads the APK from a remote URL to a local file.
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
  /// Throws [DioException] on network errors.
  Future<String> downloadApk(
    String url,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
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
