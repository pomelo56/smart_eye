import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/download_service.dart';

class _FakeDio extends DioForNative {
  _FakeDio({this.throwError}) : super(BaseOptions());

  final DioException? throwError;

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    if (throwError != null) throw throwError!;

    final file = File(savePath as String);
    await file.create(recursive: true);
    await file.writeAsString('apk content');

    onReceiveProgress?.call(11, 11);

    return Response(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadService.downloadApk', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('download_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('downloads the file and returns the save path', () async {
      final service = DownloadService(dio: _FakeDio());
      final savePath = '${tempDir.path}/smart_eye.apk';

      final result = await service.downloadApk(
        'https://example.com/app.apk',
        savePath,
      );

      expect(result, equals(savePath));
      expect(File(savePath).existsSync(), isTrue);
      expect(File(savePath).readAsStringSync(), equals('apk content'));
    });

    test('deletes an existing file before downloading', () async {
      final service = DownloadService(dio: _FakeDio());
      final savePath = '${tempDir.path}/smart_eye.apk';
      final oldFile = File(savePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('old content');

      await service.downloadApk(
        'https://example.com/app.apk',
        savePath,
      );

      expect(oldFile.readAsStringSync(), equals('apk content'));
    });

    test('reports progress via onProgress callback', () async {
      final service = DownloadService(dio: _FakeDio());
      final savePath = '${tempDir.path}/smart_eye.apk';
      final progressValues = <double>[];

      await service.downloadApk(
        'https://example.com/app.apk',
        savePath,
        onProgress: progressValues.add,
      );

      expect(progressValues, isNotEmpty);
      expect(progressValues.last, equals(1.0));
    });

    test('rethrows DioException on network failure', () async {
      final error = DioException(
        requestOptions: RequestOptions(path: 'https://example.com/app.apk'),
        error: 'network error',
      );
      final service = DownloadService(dio: _FakeDio(throwError: error));
      final savePath = '${tempDir.path}/smart_eye.apk';

      expect(
        () => service.downloadApk(
          'https://example.com/app.apk',
          savePath,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}
