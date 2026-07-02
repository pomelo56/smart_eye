/// Represents a recognized meal code with timestamp.
class MealCode {
  final String code;
  final DateTime recognizedAt;

  const MealCode({required this.code, required this.recognizedAt});

  /// Serializes to a string for storage.
  String toStorageString() => '$code|${recognizedAt.millisecondsSinceEpoch}';

  /// Deserializes from a storage string.
  static MealCode? fromStorageString(String value) {
    final parts = value.split('|');
    if (parts.length != 2) return null;
    final timestamp = int.tryParse(parts[1]);
    if (timestamp == null) return null;
    return MealCode(code: parts[0], recognizedAt: DateTime.fromMillisecondsSinceEpoch(timestamp));
  }

  /// Returns a human-readable time description.
  String get timeDescription {
    final now = DateTime.now();
    final diff = now.difference(recognizedAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '${diff.inHours} 小时前';
  }
}
