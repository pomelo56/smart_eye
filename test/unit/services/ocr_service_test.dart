import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/ocr_service.dart';

void main() {
  group('OcrService.extractMealCodes', () {
    test('extracts single meal code from text', () {
      final service = OcrService();
      final result = service.extractMealCodes('#15');
      expect(result, equals(['#15']));
    });

    test('extracts multiple meal codes from text', () {
      final service = OcrService();
      final result = service.extractMealCodes('Order #15 and #23 here');
      expect(result, equals(['#15', '#23']));
    });

    test('ignores non-meal-code numbers', () {
      final service = OcrService();
      final result =
          service.extractMealCodes('Price: \u00a520.95, phone: 13812345678');
      expect(result, isEmpty);
    });

    test('extracts from typical receipt text', () {
      final service = OcrService();
      const receipt =
          'Customer Copy\n#15 Meituan\nPaid online\nTotal \u00a520.95';
      final result = service.extractMealCodes(receipt);
      expect(result, equals(['#15']));
    });

    test('handles 1-digit and 3-digit codes', () {
      final service = OcrService();
      expect(service.extractMealCodes('#1'), equals(['#1']));
      expect(service.extractMealCodes('#999'), equals(['#999']));
    });

    test('handles 4-digit codes (JD/Ele.me platforms)', () {
      final service = OcrService();
      expect(service.extractMealCodes('#1234'), equals(['#1234']));
    });

    test('matches 5-digit codes (Pupu uses up to 6 digits)', () {
      final service = OcrService();
      expect(service.extractMealCodes('#12345'), equals(['#12345']));
    });

    test('ignores codes without hash prefix', () {
      final service = OcrService();
      final result = service.extractMealCodes('Code 15 and #16');
      expect(result, equals(['#16']));
    });

    test('ignores hash followed by non-digit', () {
      final service = OcrService();
      final result = service.extractMealCodes('#AB and #12');
      expect(result, equals(['#12']));
    });
  });

  group('OcrService.selectBestCode', () {
    test('returns null for empty list', () {
      final service = OcrService();
      expect(service.selectBestCode([]), isNull);
    });

    test('returns single code as-is', () {
      final service = OcrService();
      expect(service.selectBestCode(['#65']), equals('#65'));
    });

    test('selects longer code when multiple codes detected', () {
      final service = OcrService();
      // #1 from order number fragment, #18 from real pickup code
      expect(service.selectBestCode(['#1', '#18']), equals('#18'));
    });

    test('selects longest code from multiple candidates', () {
      final service = OcrService();
      expect(service.selectBestCode(['#1', '#18', '#234']), equals('#234'));
    });

    test('returns first code when all have same length', () {
      final service = OcrService();
      expect(service.selectBestCode(['#15', '#23']), equals('#15'));
    });

    test('handles real-world OCR scenario (#1 and #18)', () {
      final service = OcrService();
      final codes = service.extractMealCodes('#1 #18 淘宝闪购');
      expect(codes, equals(['#1', '#18']));
      expect(service.selectBestCode(codes), equals('#18'));
    });
  });

  group('OcrService.extractMealCodes (multi-platform)', () {
    test('extracts code from Meituan receipt', () {
      final service = OcrService();
      const receipt = '美团外卖\n#65\n琴阿姨筒骨骨头汤';
      expect(service.extractMealCodes(receipt), equals(['#65']));
    });

    test('extracts code from Ele.me receipt', () {
      final service = OcrService();
      const receipt = '饿了么\n#23\n订单小票';
      expect(service.extractMealCodes(receipt), equals(['#23']));
    });

    test('extracts code from JD Takeout receipt', () {
      final service = OcrService();
      const receipt = '京东外卖\n#128\n顾客备注';
      expect(service.extractMealCodes(receipt), equals(['#128']));
    });

    test('extracts code from Taobao Flash receipt', () {
      final service = OcrService();
      const receipt = '淘宝闪购\n#9\n蜂鸟配送';
      expect(service.extractMealCodes(receipt), equals(['#9']));
    });
  });

  group('OcrService.detectPlatform', () {
    test('detects Meituan', () {
      final service = OcrService();
      expect(service.detectPlatform('美团外卖 #65'), equals('美团外卖'));
    });

    test('detects Ele.me', () {
      final service = OcrService();
      expect(service.detectPlatform('饿了么 #23'), equals('饿了么'));
    });

    test('detects JD Takeout', () {
      final service = OcrService();
      expect(service.detectPlatform('京东外卖 #128'), equals('京东外卖'));
    });

    test('detects JD Takeout by short keyword', () {
      final service = OcrService();
      expect(service.detectPlatform('京东 #128'), equals('京东外卖'));
    });

    test('detects Taobao Flash', () {
      final service = OcrService();
      expect(service.detectPlatform('淘宝闪购 #9'), equals('淘宝闪购'));
    });

    test('does not match Taobao Flash by short keyword "闪购"', () {
      // "闪购" alone is too ambiguous when multiple receipts are in frame.
      final service = OcrService();
      expect(service.detectPlatform('闪购 #9'), isNull);
    });

    test('returns null for unknown platform', () {
      final service = OcrService();
      expect(service.detectPlatform('#65 随便什么'), isNull);
    });

    test('returns null for empty text', () {
      final service = OcrService();
      expect(service.detectPlatform(''), isNull);
    });
  });

  group('OcrService.detectPlatform (proximity-based)', () {
    test('detects Taobao Flash near code, ignoring Ele.me in footer', () {
      final service = OcrService();
      // Real-world: #18 淘宝闪购 at top, "登录饿了么商" at bottom
      const receipt = '#18 淘宝闪购\n粤广烧\n...\n隐私保护\n登录饿了么商';
      expect(
        service.detectPlatform(receipt, nearCode: '#18'),
        equals('淘宝闪购'),
      );
    });

    test('detects Meituan near code', () {
      final service = OcrService();
      const receipt = '#65 美团外卖\n琴阿姨筒骨骨头汤';
      expect(
        service.detectPlatform(receipt, nearCode: '#65'),
        equals('美团外卖'),
      );
    });

    test('detects JD Takeout near code', () {
      final service = OcrService();
      const receipt = '#6 京东外卖\n妙依粥店';
      expect(
        service.detectPlatform(receipt, nearCode: '#6'),
        equals('京东外卖'),
      );
    });

    test('detects Ele.me with bracket format', () {
      final service = OcrService();
      const receipt = '[饿了么] #2\n订单小票';
      expect(
        service.detectPlatform(receipt, nearCode: '#2'),
        equals('饿了么'),
      );
    });

    test('detects JD by short keyword near code', () {
      final service = OcrService();
      const receipt = '#6 京东\n妙依粥店';
      expect(
        service.detectPlatform(receipt, nearCode: '#6'),
        equals('京东外卖'),
      );
    });

    test('falls back to full-text search when code not found', () {
      final service = OcrService();
      expect(
        service.detectPlatform('美团外卖 #65', nearCode: '#999'),
        equals('美团外卖'),
      );
    });

    test('returns null when no platform keyword anywhere', () {
      final service = OcrService();
      expect(service.detectPlatform('#65 随便什么', nearCode: '#65'), isNull);
    });

    test('fuzzy matches JD Takeout when OCR misreads "京东" as "京不"', () {
      final service = OcrService();
      // Real OCR result: "6京不外卖" instead of "6京东外卖"
      const receipt = '#6 京不外卖\n妙依粥店';
      expect(
        service.detectPlatform(receipt, nearCode: '#6'),
        equals('京东外卖'),
      );
    });

    test('fuzzy matches JD Takeout in fallback search', () {
      final service = OcrService();
      expect(
        service.detectPlatform('京不外卖 #6'),
        equals('京东外卖'),
      );
    });
  });

  group('OcrService.processFrame (single-frame confirmation)', () {
    test('returns code on first frame', () {
      final service = OcrService();
      expect(service.processFrame('#15'), equals('#15'));
    });

    test('returns null on null input', () {
      final service = OcrService();
      expect(service.processFrame(null), isNull);
    });

    test('returns null for same code within 5-second cooldown', () {
      final service = OcrService();
      service.processFrame('#15'); // first frame, confirmed
      expect(service.processFrame('#15'), isNull); // in cooldown
    });

    test('returns code for different code (not in cooldown)', () {
      final service = OcrService();
      service.processFrame('#15'); // first code confirmed
      expect(service.processFrame('#23'), equals('#23'));
    });

    test('returns code again after 5-second cooldown expires', () {
      var now = DateTime(2026, 7, 5, 12, 0, 0);
      final service = OcrService(clock: () => now);
      service.processFrame('#15'); // confirmed
      now = now.add(const Duration(seconds: 5));
      expect(service.processFrame('#15'), equals('#15'));
    });

    test('clears expired cooldown entries', () {
      var now = DateTime(2026, 7, 5, 12, 0, 0);
      final service = OcrService(clock: () => now);
      service.processFrame('#15');
      service.processFrame('#23');
      now = now.add(const Duration(seconds: 6));
      service.processFrame('#99');
      expect(service.isInCooldown('#15'), isFalse);
      expect(service.isInCooldown('#23'), isFalse);
      expect(service.isInCooldown('#99'), isTrue);
    });
  });

  group('OcrService.isInCooldown', () {
    test('returns true within 5 seconds of confirmation', () {
      final service = OcrService();
      service.processFrame('#15');
      expect(service.isInCooldown('#15'), isTrue);
    });

    test('returns false for different code during cooldown', () {
      final service = OcrService();
      service.processFrame('#15');
      expect(service.isInCooldown('#23'), isFalse);
    });

    test('returns false after 5 second cooldown expires', () {
      var now = DateTime(2026, 7, 5, 12, 0, 0);
      final service = OcrService(clock: () => now);
      service.processFrame('#15');
      now = now.add(const Duration(seconds: 5));
      expect(service.isInCooldown('#15'), isFalse);
    });
  });

  group('OcrService.reset', () {
    test('clears cooldown so same code can be confirmed again', () {
      final service = OcrService();
      service.processFrame('#15'); // confirmed, in cooldown
      expect(service.isInCooldown('#15'), isTrue);
      service.reset();
      expect(service.isInCooldown('#15'), isFalse);
      expect(service.processFrame('#15'), equals('#15'));
    });

    test('clears previous code so different code is not affected', () {
      final service = OcrService();
      service.processFrame('#15'); // confirmed
      service.reset();
      expect(service.processFrame('#23'), equals('#23'));
    });
  });
}
