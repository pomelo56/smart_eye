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
      final result = service.extractMealCodes('Price: \u00a520.95, phone: 13812345678');
      expect(result, isEmpty);
    });

    test('extracts from typical receipt text', () {
      final service = OcrService();
      const receipt = 'Customer Copy\n#15 Meituan\nPaid online\nTotal \u00a520.95';
      final result = service.extractMealCodes(receipt);
      expect(result, equals(['#15']));
    });

    test('handles 1-digit and 3-digit codes', () {
      final service = OcrService();
      expect(service.extractMealCodes('#1'), equals(['#1']));
      expect(service.extractMealCodes('#999'), equals(['#999']));
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

  group('OcrService.processFrame', () {
    test('returns null on first frame', () {
      final service = OcrService();
      expect(service.processFrame('#15'), isNull);
    });

    test('returns code when two consecutive frames match', () {
      final service = OcrService();
      service.processFrame('#15');
      expect(service.processFrame('#15'), equals('#15'));
    });

    test('returns null when two consecutive frames differ', () {
      final service = OcrService();
      service.processFrame('#15');
      expect(service.processFrame('#23'), isNull);
    });

    test('resets frame counter after mismatch', () {
      final service = OcrService();
      service.processFrame('#15'); // frame 1
      service.processFrame('#23'); // mismatch, resets
      expect(service.processFrame('#23'), isNull); // frame 1 again
      expect(service.processFrame('#23'), equals('#23')); // frame 2 match
    });

    test('returns null on null input', () {
      final service = OcrService();
      expect(service.processFrame(null), isNull);
    });

    test('ignores second match of same code (no duplicate frames needed)', () {
      final service = OcrService();
      service.processFrame('#15');
      expect(service.processFrame('#15'), equals('#15'));
      // After confirmation, subsequent same frames should not re-confirm immediately
      expect(service.processFrame('#15'), isNull);
    });
  });

  group('OcrService.isInCooldown', () {
    test('returns true within 5 seconds of confirmation', () {
      final service = OcrService();
      service.processFrame('#15');
      service.processFrame('#15'); // confirmed
      expect(service.isInCooldown('#15'), isTrue);
    });

    test('returns false for different code during cooldown', () {
      final service = OcrService();
      service.processFrame('#15');
      service.processFrame('#15'); // confirmed
      expect(service.isInCooldown('#23'), isFalse);
    });

    test('returns false after 5 second cooldown expires', () async {
      final service = OcrService();
      service.processFrame('#15');
      service.processFrame('#15'); // confirmed
      await Future.delayed(const Duration(seconds: 5));
      expect(service.isInCooldown('#15'), isFalse);
    });
  });
}
