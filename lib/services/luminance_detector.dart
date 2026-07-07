import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Coarse luminance category used to decide whether to suggest turning
/// the torch on.
///
/// The thresholds are deliberately generous: a frame that *looks* dim
/// to a human is what we care about, not a precise photometric value.
/// 40/255 is roughly the "you can read the text but it's straining"
/// boundary on a phone screen, and 80/255 is the "comfortable" boundary.
enum LuminanceBucket { dark, normal, bright }

/// Result of [LuminanceDetector.analyze].
class LuminanceResult {
  const LuminanceResult({required this.luminance, required this.bucket});

  /// Mean luminance of the analyzed frame, 0-255.
  final int luminance;

  /// Coarse bucket derived from [luminance].
  final LuminanceBucket bucket;

  /// True when the frame is dark enough that the user is likely to
  /// have trouble reading the receipt. The caller should:
  /// 1. Play the "lighting is dim" voice prompt (with the 8s cooldown
  ///    the rest of the app uses for distance feedback).
  /// 2. Try to turn the torch on.
  bool get shouldSuggestTorch => bucket == LuminanceBucket.dark;
}

/// Analyzes a YUV420 frame's Y (luma) plane and returns its mean
/// luminance and a coarse bucket.
///
/// The Y plane is grayscale and represents what the human eye perceives
/// as brightness — it is the right input for a "can the user see this?"
/// check, and it is 1/3 the size of an RGB frame, so it is cheap to
/// scan. The [camera] plugin exposes the Y plane via
/// `CameraImage.planes[0]`.
///
/// Sampling: the analyzer does not need to visit every pixel to make a
/// good decision. A 64-cell grid (8x8 samples) is statistically
/// representative for a phone camera frame and runs in well under 1 ms
/// in release mode. Sampling more cells does not meaningfully change
/// the result, but does increase cost linearly.
class LuminanceDetector {
  /// Number of cells per axis to sample. 8x8 = 64 samples is enough to
  /// cover a 720p frame at 90x90 pixel granularity.
  static const int _gridSize = 8;

  /// Bucket thresholds. Luminance is integer 0-255.
  static const int darkThreshold = 40;
  static const int brightThreshold = 200;

  /// Analyzes a YUV420 Y plane and returns the mean luminance and bucket.
  ///
  /// [yPlaneBytes] must be the raw bytes of the Y plane (plane index 0
  /// in `CameraImage.planes`). [yPlaneRowStride] is the number of bytes
  /// per row of the Y plane (may be larger than [width] when the camera
  /// uses padding for alignment). [yPlanePixelStride] is the byte
  /// distance between adjacent pixels in the Y plane; on YUV420 this
  /// is always 1, but we accept the value to be safe.
  static LuminanceResult analyze({
    required Uint8List yPlaneBytes,
    required int yPlaneRowStride,
    required int yPlanePixelStride,
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      // Empty frame: treat as dark so the user gets prompted.
      return const LuminanceResult(
        luminance: 0,
        bucket: LuminanceBucket.dark,
      );
    }

    final cellW = math.max(1, width ~/ _gridSize);
    final cellH = math.max(1, height ~/ _gridSize);

    var sum = 0;
    var count = 0;

    for (var gy = 0; gy < _gridSize; gy++) {
      final y = (gy * cellH).clamp(0, height - 1);
      for (var gx = 0; gx < _gridSize; gx++) {
        final x = (gx * cellW).clamp(0, width - 1);
        final byteIndex = y * yPlaneRowStride + x * yPlanePixelStride;
        if (byteIndex < 0 || byteIndex >= yPlaneBytes.length) {
          // Defensive: out-of-bounds means the stride/width combo is
          // inconsistent. Skip rather than crash.
          continue;
        }
        sum += yPlaneBytes[byteIndex];
        count++;
      }
    }

    return _buildResult(sum, count);
  }

  /// Analyzes an RGBA8888 buffer and returns the mean luminance.
  ///
  /// This is the path used when the camera delivers JPEG (e.g. via
  /// `takePicture()`) and we decode it through `dart:ui`. The input
  /// must be 4 bytes per pixel in R, G, B, A order — exactly what
  /// `ui.Image.toByteData(format: ImageByteFormat.rawRgba)` produces.
  ///
  /// We compute luminance using the BT.601 luma weights because they
  /// approximate what a human eye perceives better than a naive
  /// (R+G+B)/3 average. The result is rounded to an int 0-255 to match
  /// the Y-plane path's output range and the [LuminanceBucket]
  /// thresholds.
  static LuminanceResult analyzeRgba({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      return const LuminanceResult(
        luminance: 0,
        bucket: LuminanceBucket.dark,
      );
    }

    final cellW = math.max(1, width ~/ _gridSize);
    final cellH = math.max(1, height ~/ _gridSize);
    final stride = width * 4;

    var sum = 0;
    var count = 0;

    for (var gy = 0; gy < _gridSize; gy++) {
      final y = (gy * cellH).clamp(0, height - 1);
      for (var gx = 0; gx < _gridSize; gx++) {
        final x = (gx * cellW).clamp(0, width - 1);
        final pixelOffset = y * stride + x * 4;
        if (pixelOffset + 2 >= rgbaBytes.length) {
          continue;
        }
        // BT.601 luma (same weights the YUV Y plane uses, so the bucket
        // thresholds below are consistent across paths).
        final r = rgbaBytes[pixelOffset];
        final g = rgbaBytes[pixelOffset + 1];
        final b = rgbaBytes[pixelOffset + 2];
        // 0.299 R + 0.587 G + 0.114 B
        final luma = (0.299 * r + 0.587 * g + 0.114 * b).round();
        sum += luma;
        count++;
      }
    }

    return _buildResult(sum, count);
  }

  static LuminanceResult _buildResult(int sum, int count) {
    if (count == 0) {
      return const LuminanceResult(
        luminance: 0,
        bucket: LuminanceBucket.dark,
      );
    }
    final mean = sum ~/ count;
    final bucket = mean < darkThreshold
        ? LuminanceBucket.dark
        : (mean > brightThreshold
            ? LuminanceBucket.bright
            : LuminanceBucket.normal);
    return LuminanceResult(luminance: mean, bucket: bucket);
  }
}

/// Wraps a [CameraController] to provide idempotent torch on/off with
/// graceful handling of unsupported hardware.
///
/// The [camera] plugin throws [CameraException] if the device does not
/// support torch (rare, but happens on some emulators and very old
/// hardware). We catch that and report failure to the caller rather
/// than crashing the scanning loop.
class TorchController {
  TorchController({required CameraController controller})
      : _controller = controller;

  final CameraController _controller;
  bool _isOn = false;

  bool get isOn => _isOn;

  /// Turns the torch on (or off).
  ///
  /// Returns true if the camera accepted the new flash mode, false if
  /// the hardware refused (e.g. the device has no torch). The caller
  /// should speak a "torch failed, please enable it manually" prompt
  /// on false.
  Future<bool> setTorch(bool on) async {
    if (on == _isOn) {
      // Idempotent: do not spam setFlashMode. The camera plugin
      // accepts a redundant call but it still costs a native IPC.
      return true;
    }
    final mode = on ? FlashMode.torch : FlashMode.off;
    try {
      await _controller.setFlashMode(mode);
      _isOn = on;
      return true;
    } on CameraException {
      // Hardware refused. We deliberately do not log here — the caller
      // (HomeScreen) is responsible for surfacing the failure as a
      // voice prompt and an entry in the on-screen log.
      _isOn = false;
      return false;
    }
  }
}
