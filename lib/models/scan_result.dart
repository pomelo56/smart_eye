import 'dart:ui';

/// Represents a single detected meal code with its platform and screen position.
class ScanResult {
  /// The meal code, e.g. "#65".
  final String code;

  /// Platform display name, e.g. "美团外卖". Null if unknown.
  final String? platform;

  /// Human-readable position label, e.g. "左上", "右下", "中间".
  final String positionLabel;

  /// Bounding box center in image coordinates (for sorting).
  final Offset center;

  ScanResult({
    required this.code,
    this.platform,
    required this.positionLabel,
    required this.center,
  });

  @override
  String toString() =>
      'ScanResult(code=$code, platform=$platform, pos=$positionLabel)';
}

/// Computes a position label from a point relative to the overall text extent.
///
/// Divides the text area into a 3×3 grid and returns the Chinese label
/// for the zone the point falls in.
String computePositionLabel(Offset point, Rect textBounds) {
  if (textBounds.isEmpty) return '中间';

  final xRatio = (point.dx - textBounds.left) / textBounds.width;
  final yRatio = (point.dy - textBounds.top) / textBounds.height;

  String xLabel;
  if (xRatio < 0.33) {
    xLabel = '左';
  } else if (xRatio > 0.66) {
    xLabel = '右';
  } else {
    xLabel = '';
  }

  String yLabel;
  if (yRatio < 0.33) {
    yLabel = '上';
  } else if (yRatio > 0.66) {
    yLabel = '下';
  } else {
    yLabel = '';
  }

  final combined = '$xLabel$yLabel';
  if (combined.isEmpty) return '中间';
  if (combined == '左' || combined == '右') return '$combined侧';
  if (combined == '上') return '上方';
  if (combined == '下') return '下方';
  return combined; // 左上, 右上, 左下, 右下
}

/// Maps a position label to its audio asset path.
String? positionAudioAsset(String? label) {
  if (label == null) return null;
  switch (label) {
    case '左上':
      return 'assets/audio/pos_topleft.mp3';
    case '右上':
      return 'assets/audio/pos_topright.mp3';
    case '左下':
      return 'assets/audio/pos_bottomleft.mp3';
    case '右下':
      return 'assets/audio/pos_bottomright.mp3';
    case '上方':
      return 'assets/audio/pos_top.mp3';
    case '下方':
      return 'assets/audio/pos_bottom.mp3';
    case '中间':
      return 'assets/audio/pos_center.mp3';
    case '左侧':
      return 'assets/audio/pos_left.mp3';
    case '右侧':
      return 'assets/audio/pos_right.mp3';
    default:
      return null;
  }
}
