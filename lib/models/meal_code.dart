/// Represents a recognized meal code with timestamp and platform.
class MealCode {
  final String code;
  final DateTime recognizedAt;
  final String? platform;

  const MealCode({
    required this.code,
    required this.recognizedAt,
    this.platform,
  });

  /// Serializes to a pipe-delimited string for storage.
  /// Format: `code|timestamp|platform` (platform optional, backward compatible).
  String toStorageString() {
    final plat = platform ?? '';
    return '$code|${recognizedAt.millisecondsSinceEpoch}|$plat';
  }

  /// Deserializes from a pipe-delimited string.
  /// Supports both old format (`code|timestamp`) and new format (`code|timestamp|platform`).
  static MealCode? fromStorageString(String value) {
    final parts = value.split('|');
    if (parts.length < 2) return null;
    final timestamp = int.tryParse(parts[1]);
    if (timestamp == null) return null;
    final platform = parts.length >= 3 && parts[2].isNotEmpty ? parts[2] : null;
    return MealCode(
      code: parts[0],
      recognizedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      platform: platform,
    );
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
