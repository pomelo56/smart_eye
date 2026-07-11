import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_code.dart';

/// Stores and retrieves the user's recent meal-code recognitions.
///
/// Records are kept in [SharedPreferences] as a list of pipe-delimited strings.
/// Entries older than 24 hours are automatically discarded on read.
///
/// **CVE-STYLE-008:** Storage strings are XOR-obfuscated with a fixed key
/// before being written to SharedPreferences. This is not strong encryption
/// (a fixed app key is recoverable from the binary) but prevents casual
/// inspection via `adb shell run-as cat shared_prefs/*.xml` from revealing
/// meal codes in plaintext. Strong encryption (flutter_secure_storage /
/// Android Keystore) is deferred to a future release when higher-sensitivity
/// data needs to be persisted.
class HistoryService {
  static const _storageKey = 'meal_code_history';
  static const _maxRecords = 5;
  static const _retentionPeriod = Duration(hours: 24);

  /// Fixed XOR key — deliberately not a secret, just enough to block grep.
  static const List<int> _obfuscationKey = [
    0x53, 0x6D, 0x61, 0x72, 0x74, 0x45, 0x79, 0x65, // SmartEye
    0x56, 0x30, 0x2E, 0x38, 0x2E, 0x36 // v0.8.6
  ];

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
          DateTime.now().difference(last.recognizedAt) <
              const Duration(seconds: 5)) {
        return;
      }
    }

    records.insert(0,
        MealCode(code: code, recognizedAt: DateTime.now(), platform: platform));

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

  /// XOR-obfuscates a plaintext string so it is not human-readable in
  /// shared_prefs XML.
  /// Visible for testing only — do not call from production code.
  static String obfuscateForTest(String plain) => _obfuscate(plain);

  static String _obfuscate(String plain) {
    final bytes = utf8.encode(plain);
    final out = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      out.add(bytes[i] ^ _obfuscationKey[i % _obfuscationKey.length]);
    }
    return base64.encode(out);
  }

  /// Reverses [_obfuscate]. Returns empty string on decode failure so that
  /// corrupt or legacy (pre-v0.8.6) entries degrade gracefully.
  static String _deobfuscate(String encoded) {
    try {
      final bytes = base64.decode(encoded);
      final out = <int>[];
      for (var i = 0; i < bytes.length; i++) {
        out.add(bytes[i] ^ _obfuscationKey[i % _obfuscationKey.length]);
      }
      return utf8.decode(out, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<List<MealCode>> _readRecords() async {
    final raw = _prefs.getStringList(_storageKey) ?? [];
    return raw
        .map(_deobfuscate) // CVE-STYLE-008: deobfuscate before parsing
        .map(MealCode.fromStorageString)
        .whereType<MealCode>()
        .toList();
  }

  Future<void> _writeRecords(List<MealCode> records) async {
    // CVE-STYLE-008: obfuscate before writing
    final raw = records.map((r) => _obfuscate(r.toStorageString())).toList();
    await _prefs.setStringList(_storageKey, raw);
  }
}
