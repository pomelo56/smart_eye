import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_code.dart';

/// Stores and retrieves the user's recent meal-code recognitions.
///
/// Records are kept in [SharedPreferences] as a list of pipe-delimited strings.
/// Entries older than 24 hours are automatically discarded on read.
class HistoryService {
  static const _storageKey = 'meal_code_history';
  static const _maxRecords = 5;
  static const _retentionPeriod = Duration(hours: 24);

  final SharedPreferences _prefs;

  /// Creates a service using the provided [SharedPreferences] instance.
  HistoryService({required SharedPreferences prefs}) : _prefs = prefs;

  /// Adds a new recognition record.
  ///
  /// If the same code was already recorded within the last 5 seconds, it is
  /// ignored to avoid rapid duplicates from the multi-frame validation logic.
  Future<void> add(String code, {String? platform}) async {
    if (code.isEmpty) return;

    final records = await _readRecords();

    // Avoid rapid duplicates (within 5 seconds).
    if (records.isNotEmpty) {
      final last = records.first;
      if (last.code == code &&
          DateTime.now().difference(last.recognizedAt) < const Duration(seconds: 5)) {
        return;
      }
    }

    records.insert(0, MealCode(code: code, recognizedAt: DateTime.now(), platform: platform));

    while (records.length > _maxRecords) {
      records.removeLast();
    }

    await _writeRecords(records);
  }

  /// Returns the recent records, newest first, with expired entries removed.
  Future<List<MealCode>> getRecent() async {
    final records = await _readRecords();
    final now = DateTime.now();
    final valid = records
        .where((r) => now.difference(r.recognizedAt) < _retentionPeriod)
        .toList();

    if (valid.length != records.length) {
      await _writeRecords(valid);
    }

    return valid;
  }

  /// Clears all stored records.
  Future<void> clear() async {
    await _prefs.remove(_storageKey);
  }

  Future<List<MealCode>> _readRecords() async {
    final raw = _prefs.getStringList(_storageKey) ?? [];
    return raw
        .map(MealCode.fromStorageString)
        .whereType<MealCode>()
        .toList();
  }

  Future<void> _writeRecords(List<MealCode> records) async {
    final raw = records.map((r) => r.toStorageString()).toList();
    await _prefs.setStringList(_storageKey, raw);
  }
}
