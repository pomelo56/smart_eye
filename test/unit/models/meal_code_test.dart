import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/models/meal_code.dart';

void main() {
  group('MealCode', () {
    test('serializes and deserializes correctly', () {
      final code =
          MealCode(code: '#15', recognizedAt: DateTime(2026, 6, 30, 12, 0));
      final storage = code.toStorageString();
      final restored = MealCode.fromStorageString(storage);
      expect(restored?.code, equals('#15'));
      expect(restored?.recognizedAt, equals(DateTime(2026, 6, 30, 12, 0)));
    });

    test('returns null for invalid storage string', () {
      expect(MealCode.fromStorageString('invalid'), isNull);
      expect(MealCode.fromStorageString(''), isNull);
    });

    test('time description shows "刚刚" for recent codes', () {
      final code = MealCode(
          code: '#15',
          recognizedAt: DateTime.now().subtract(const Duration(seconds: 30)));
      expect(code.timeDescription, equals('刚刚'));
    });

    test('time description shows minutes for older codes', () {
      final code = MealCode(
          code: '#15',
          recognizedAt: DateTime.now().subtract(const Duration(minutes: 5)));
      expect(code.timeDescription, equals('5 分钟前'));
    });
  });
}
