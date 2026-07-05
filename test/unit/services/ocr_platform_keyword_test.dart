import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/ocr_service.dart';

void main() {
  group('OcrService.hasPlatformKeyword', () {
    test('returns true when text contains 美团外卖', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('美团外卖 #65'), isTrue);
    });

    test('returns true when text contains 饿了么', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('饿了么 订单详情'), isTrue);
    });

    test('returns true when text contains 京东外卖', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('京东外卖 取餐码'), isTrue);
    });

    test('returns true when text contains 淘宝闪购', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('淘宝闪购 即将送达'), isTrue);
    });

    test('returns true when text contains 朴朴超市', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('朴朴超市 #586132'), isTrue);
    });

    test('returns true when text contains the short form 美团', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('美团 #15'), isTrue);
    });

    test('returns true for fuzzy JD keyword 京不外卖 (OCR misread)', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('京不外卖 订单'), isTrue);
    });

    test('returns false for plain text without platform keywords', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword('Price: ¥20.95'), isFalse);
    });

    test('returns false for empty text', () {
      final service = OcrService();
      expect(service.hasPlatformKeyword(''), isFalse);
    });
  });
}
