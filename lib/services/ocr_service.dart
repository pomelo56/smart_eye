/// Service for extracting and validating meal codes from OCR text.
///
/// Supports the format `#` + 1-3 digits (e.g., `#15`) used by Meituan.
/// Implements multi-frame validation (2 consecutive matches required)
/// and a 5-second cooldown to prevent duplicate announcements.
class OcrService {
  static final _mealCodeRegex = RegExp(r'#(\d{1,3})');

  String? _pendingCode;
  String? _confirmedCode;
  DateTime? _confirmationTime;

  /// Extracts all meal codes from the given text.
  List<String> extractMealCodes(String text) {
    return _mealCodeRegex
        .allMatches(text)
        .map((m) => '#${m.group(1)}')
        .toList();
  }

  /// Processes a new frame for multi-frame validation.
  ///
  /// Returns the confirmed code only when two consecutive frames match.
  /// Returns null otherwise.
  String? processFrame(String? code) {
    if (code == null) {
      _pendingCode = null;
      return null;
    }

    if (_pendingCode == null) {
      // First frame after reset
      _pendingCode = code;
      return null;
    }

    if (_pendingCode == code) {
      // Two consecutive frames match
      _confirmedCode = code;
      _confirmationTime = DateTime.now();
      _pendingCode = null; // Reset to prevent immediate re-confirmation
      return code;
    }

    // Mismatch: reset
    _pendingCode = null;
    return null;
  }

  /// Checks if the given code is within the 5-second cooldown period.
  bool isInCooldown(String code) {
    if (_confirmedCode != code || _confirmationTime == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(_confirmationTime!);
    return elapsed < const Duration(seconds: 5);
  }
}
