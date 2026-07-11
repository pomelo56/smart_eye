import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_eye/services/history_service.dart';

void main() {
  group('HistoryService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    Future<HistoryService> createService() async {
      final prefs = await SharedPreferences.getInstance();
      return HistoryService(prefs: prefs);
    }

    test('add stores a new record', () async {
      final service = await createService();
      await service.add('#15');
      final records = await service.getRecent();
      expect(records.length, equals(1));
      expect(records.first.code, equals('#15'));
    });

    test('ignores duplicate within 5 seconds', () async {
      final service = await createService();
      await service.add('#15');
      await service.add('#15');
      final records = await service.getRecent();
      expect(records.length, equals(1));
    });

    test('keeps different codes as separate records', () async {
      final service = await createService();
      await service.add('#15');
      await service.add('#23');
      final records = await service.getRecent();
      expect(records.length, equals(2));
    });

    test('keeps at most 5 records', () async {
      final service = await createService();
      for (var i = 0; i < 10; i++) {
        await service.add('#$i');
      }
      final records = await service.getRecent();
      expect(records.length, equals(5));
    });

    test('newest records replace oldest when limit exceeded', () async {
      final service = await createService();
      await service.add('#1');
      await service.add('#2');
      await service.add('#3');
      await service.add('#4');
      await service.add('#5');
      await service.add('#6');
      final records = await service.getRecent();
      expect(records.first.code, equals('#6'));
      expect(records.map((r) => r.code).toList(),
          containsAll(['#2', '#3', '#4', '#5', '#6']));
    });

    test('drops records older than 24 hours', () async {
      // CVE-STYLE-008: Storage is now XOR+Base64 obfuscated, so we must
      // obfuscate test data before writing it to mock SharedPreferences.
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'meal_code_history': [
          HistoryService.obfuscateForTest(
              '#fresh|${now.millisecondsSinceEpoch}'),
          HistoryService.obfuscateForTest(
              '#old|${now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch}'),
        ],
      });
      final service = await createService();
      final records = await service.getRecent();
      expect(records.length, equals(1));
      expect(records.first.code, equals('#fresh'));
    });

    test('clear removes all records', () async {
      final service = await createService();
      await service.add('#15');
      await service.clear();
      final records = await service.getRecent();
      expect(records, isEmpty);
    });
  });
}
