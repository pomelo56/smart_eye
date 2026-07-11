import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/apk_verifier.dart';

void main() {
  group('ApkVerifier', () {
    late ApkVerifier verifier;

    setUp(() {
      verifier = ApkVerifier();
    });

    test('空路径应返回false', () async {
      final result = await verifier.isApkTrusted('');
      expect(result, isFalse);
    });

    test('不存在的APK文件应返回false', () async {
      final result = await verifier.isApkTrusted('/nonexistent/path/to.apk');
      expect(result, isFalse);
    });
  });
}
