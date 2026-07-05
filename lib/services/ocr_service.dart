/// Service for extracting and validating meal codes from OCR text.
///
/// Supports multiple delivery platforms:
/// - 美团外卖 (Meituan): `#65 美团外卖`
/// - 饿了么 (Ele.me): `[ 饿了么 ] #2`
/// - 京东外卖 (JD Takeout): `#6 京东外卖`
/// - 淘宝闪购 (Taobao Flash): `#18 淘宝闪购`
/// - 美团闪购 (Meituan Flash): `#92 美团闪购`
/// - 朴朴超市 (Pupu): `朴朴超市 #586132`
/// - 美团直送 (Meituan Direct): `美团-261`
///
/// The pickup code and platform name always appear together on the receipt.
/// We use proximity-based detection: find the platform keyword closest to
/// the pickup code to avoid false matches from footer text like
/// "登录饿了么商家版".
///
/// Single-frame confirmation with 5-second cooldown to prevent duplicates.
class OcrService {
  /// Creates an [OcrService].
  ///
  /// The optional [clock] is used in tests to control time without real
  /// delays.
  OcrService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Matches `#` followed by 1-6 digits (covers all major platforms including
  /// 朴朴超市's 6-digit codes).
  static final _mealCodeRegex = RegExp(r'#(\d{1,6})');

  /// Matches `美团-数字` format (e.g. `美团-261`).
  static final _meituanDashRegex = RegExp(r'美团-(\d{1,6})');

  /// Platform detection rules, ordered by priority (most specific first).
  /// Short keywords like "闪购" are excluded to avoid false matches when
  /// multiple receipts are in the same frame.
  static const _platformRules = <_PlatformRule>[
    _PlatformRule('淘宝闪购', '淘宝闪购'),
    _PlatformRule('美团闪购', '美团闪购'),
    _PlatformRule('朴朴超市', '朴朴超市'),
    _PlatformRule('朴朴', '朴朴超市'),
    _PlatformRule('京东外卖', '京东外卖'),
    _PlatformRule('京东', '京东外卖'),
    _PlatformRule('美团外卖', '美团外卖'),
    _PlatformRule('美团', '美团外卖'),
    _PlatformRule('饿了么', '饿了么'),
  ];

  /// Maximum character distance between a code and its platform keyword.
  /// Only keywords within this window are considered, preventing
  /// cross-receipt misidentification when multiple receipts are in frame.
  static const proximityMaxDistance = 8;

  /// Fuzzy regex for JD Takeout: "京" + 0-2 chars + "外卖".
  /// OCR on thermal paper often misreads "京东外卖" as "京不外卖" etc.
  static final _jdFuzzyRegex = RegExp(r'京.{0,2}外卖');

  /// Per-code cooldown map: code → expiry time.
  /// Allows detecting new codes while suppressing repeats.
  final Map<String, DateTime> _cooldownMap = {};

  /// Cooldown duration: 5 seconds per code.
  static const _cooldownDuration = Duration(seconds: 5);

  /// Extracts all meal codes from the given text.
  ///
  /// Supports two formats:
  /// - `#数字` (1-6 digits) — standard format for most platforms
  /// - `美团-数字` — Meituan direct delivery format
  List<String> extractMealCodes(String text) {
    final codes = <String>{};

    // Standard # + digits format
    for (final match in _mealCodeRegex.allMatches(text)) {
      codes.add('#${match.group(1)}');
    }

    // 美团-数字 format (no # prefix)
    for (final match in _meituanDashRegex.allMatches(text)) {
      codes.add('#${match.group(1)}');
    }

    return codes.toList();
  }

  /// Selects the best meal code from a list of candidates.
  ///
  /// When OCR detects multiple codes (e.g. `#1` from order number and `#18`
  /// from the actual pickup code), we pick the one with the most digits,
  /// because the real pickup code is usually longer than accidental matches
  /// from long order numbers.
  ///
  /// If multiple codes have the same length, returns the first one.
  String? selectBestCode(List<String> codes) {
    if (codes.isEmpty) return null;
    if (codes.length == 1) return codes.first;

    String best = codes.first;
    for (final code in codes.skip(1)) {
      if (code.length > best.length) {
        best = code;
      }
    }
    return best;
  }

  /// Detects which delivery platform the text belongs to.
  ///
  /// Uses proximity-based detection: scans the text for each platform keyword
  /// and returns the one whose position is closest to the pickup code.
  /// This prevents misclassification when a receipt mentions another platform
  /// in its footer (e.g. 淘宝闪购 receipt says "登录饿了么商家版").
  ///
  /// Falls back to priority-ordered full-text search if no code is found
  /// or no keyword is near the code.
  String? detectPlatform(String text, {String? nearCode}) {
    // Special case: 美团-数字 format always maps to 美团外卖
    if (nearCode != null && _meituanDashRegex.hasMatch(text)) {
      final dashMatch = _meituanDashRegex.firstMatch(text);
      if (dashMatch != null && '#${dashMatch.group(1)}' == nearCode) {
        return '美团外卖';
      }
    }

    // If we have a code, try proximity-based detection first.
    if (nearCode != null) {
      final codeIndex = text.indexOf(nearCode);
      if (codeIndex >= 0) {
        String? bestPlatform;
        // Tight window: platform name must be within proximityMaxDistance
        // chars of the code. This prevents matching a platform keyword from
        // an adjacent receipt.
        const maxDistance = proximityMaxDistance;
        int bestDistance = maxDistance + 1;
        for (final rule in _platformRules) {
          int searchFrom = 0;
          while (true) {
            final idx = text.indexOf(rule.keyword, searchFrom);
            if (idx < 0) break;
            final distance = (idx - codeIndex).abs();
            if (distance < bestDistance) {
              bestDistance = distance;
              bestPlatform = rule.platform;
            }
            searchFrom = idx + rule.keyword.length;
          }
        }
        // Fuzzy match for JD Takeout (OCR may misread "京东外卖" as "京不外卖").
        if (bestPlatform == null) {
          for (final match in _jdFuzzyRegex.allMatches(text)) {
            final distance = (match.start - codeIndex).abs();
            if (distance < bestDistance) {
              bestDistance = distance;
              bestPlatform = '京东外卖';
            }
          }
        }
        if (bestPlatform != null) return bestPlatform;
      }
    }

    // Fallback: priority-ordered full-text search.
    for (final rule in _platformRules) {
      if (text.contains(rule.keyword)) {
        return rule.platform;
      }
    }
    // Fuzzy fallback for JD Takeout.
    if (_jdFuzzyRegex.hasMatch(text)) {
      return '京东外卖';
    }
    return null;
  }

  /// Processes a new frame for validation.
  ///
  /// Returns the code immediately if not in cooldown, null otherwise.
  String? processFrame(String? code) {
    if (code == null) return null;

    _cleanupExpiredCooldowns();
    if (!_isInCooldown(code)) {
      _cooldownMap[code] = _clock().add(_cooldownDuration);
      return code;
    }
    return null;
  }

  /// Removes expired entries from the cooldown map to avoid unbounded growth.
  void _cleanupExpiredCooldowns() {
    final now = _clock();
    _cooldownMap.removeWhere((_, expiry) => now.isAfter(expiry));
  }

  /// Checks if the given code is within the cooldown period.
  bool _isInCooldown(String code) {
    final expiry = _cooldownMap[code];
    if (expiry == null) return false;
    return _clock().isBefore(expiry);
  }

  /// Public cooldown check.
  bool isInCooldown(String code) => _isInCooldown(code);

  /// Resets the confirmation state and cooldown.
  ///
  /// Called when the user requests a re-scan via triple-tap.
  void reset() {
    _cooldownMap.clear();
  }
}

/// A platform detection rule pairing a keyword to a display name.
class _PlatformRule {
  final String keyword;
  final String platform;

  const _PlatformRule(this.keyword, this.platform);
}
