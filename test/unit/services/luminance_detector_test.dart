import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/luminance_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LuminanceDetector.analyze()', () {
    test('returns dark for a fully-black frame', () async {
      // 8x8 black image, all 0 bytes in Y plane.
      final black = Uint8List.fromList(List<int>.filled(64, 0));
      final result = LuminanceDetector.analyze(
        yPlaneBytes: black,
        yPlaneRowStride: 8,
        yPlanePixelStride: 1,
        width: 8,
        height: 8,
      );
      expect(result.luminance, 0);
      expect(result.bucket, LuminanceBucket.dark);
    });

    test('returns bright for a fully-white frame', () async {
      // 8x8 white image, all 235 in Y plane (BT.601 white is 235 in
      // limited range, 255 in full range; we use 255 here).
      final white = Uint8List.fromList(List<int>.filled(64, 255));
      final result = LuminanceDetector.analyze(
        yPlaneBytes: white,
        yPlaneRowStride: 8,
        yPlanePixelStride: 1,
        width: 8,
        height: 8,
      );
      expect(result.luminance, 255);
      expect(result.bucket, LuminanceBucket.bright);
    });

    test('returns dark for an underexposed indoor frame (avg ~20)', () async {
      // Simulate dim room: most pixels near 10, a few highlights at 30.
      // 90 pixels at 10 + 10 pixels at 30 → mean = 12, safely below 40.
      final bytes = Uint8List.fromList(
        List<int>.generate(100, (i) => i.isEven ? 10 : 30),
      );
      final result = LuminanceDetector.analyze(
        yPlaneBytes: bytes,
        yPlaneRowStride: 10,
        yPlanePixelStride: 1,
        width: 10,
        height: 10,
      );
      // Note: this is a 10x10 frame, the detector samples 8x8=64 of
      // those pixels. The exact sampled mean may be 12 or 20 depending
      // on the stride, but it will be in the dark range.
      expect(result.luminance, lessThan(40));
      expect(result.bucket, LuminanceBucket.dark);
    });

    test('returns normal for a well-lit frame (avg ~128)', () async {
      // Mid-gray: roughly 128 across the frame.
      final bytes = Uint8List.fromList(List<int>.filled(64, 128));
      final result = LuminanceDetector.analyze(
        yPlaneBytes: bytes,
        yPlaneRowStride: 8,
        yPlanePixelStride: 1,
        width: 8,
        height: 8,
      );
      // Expect luminance in the 40-200 "normal" range.
      expect(result.luminance, inInclusiveRange(120, 135));
      expect(result.bucket, LuminanceBucket.normal);
    });

    test('respects pixel stride (subsampled YUV420)', () async {
      // Some camera frames deliver YUV420 where the Y plane uses stride
      // > width. The detector must skip stride-padding bytes.
      // 4x4 logical image, 8-byte row stride (4 bytes padding per row).
      // Each row: 4 real pixels + 4 padding bytes (which are 0).
      // If we did not respect stride, the padding zeros would drag the
      // average down and the frame would look darker than it is.
      // Use 210 (just above the bright threshold of 200) to make the
      // test robust against the bright-vs-normal boundary.
      final strideBytes = <int>[
        210, 210, 210, 210, 0, 0, 0, 0, // row 0
        210, 210, 210, 210, 0, 0, 0, 0, // row 1
        210, 210, 210, 210, 0, 0, 0, 0, // row 2
        210, 210, 210, 210, 0, 0, 0, 0, // row 3
      ];
      final result = LuminanceDetector.analyze(
        yPlaneBytes: Uint8List.fromList(strideBytes),
        yPlaneRowStride: 8,
        yPlanePixelStride: 1,
        width: 4,
        height: 4,
      );
      expect(result.luminance, 210,
          reason: 'Padding bytes must be skipped; otherwise the average '
              'would be dragged below the bright threshold.');
      expect(result.bucket, LuminanceBucket.bright);
    });

    test('returns normal for a frame near the dark threshold (40)', () async {
      // 100 pixels at exactly 40 — the dark/normal boundary.
      final bytes = Uint8List.fromList(List<int>.filled(100, 40));
      final result = LuminanceDetector.analyze(
        yPlaneBytes: bytes,
        yPlaneRowStride: 10,
        yPlanePixelStride: 1,
        width: 10,
        height: 10,
      );
      // 40 is the boundary value itself; the bucket should be normal
      // because the trigger is "< 40" (strictly less).
      expect(result.luminance, 40);
      expect(result.bucket, LuminanceBucket.normal);
    });

    test('subsamples large frames to keep analyze() under 50 ms', () async {
      // 1280x720 image, 921600 pixels. The detector should sample a
      // small grid (e.g. 64 pixels) rather than touching every byte.
      final bytes = Uint8List.fromList(List<int>.filled(1280 * 720, 128));
      final stopwatch = Stopwatch()..start();
      final result = LuminanceDetector.analyze(
        yPlaneBytes: bytes,
        yPlaneRowStride: 1280,
        yPlanePixelStride: 1,
        width: 1280,
        height: 720,
      );
      stopwatch.stop();
      // Soft target: < 50 ms even on a debug Dart VM. Release build
      // will be much faster. We give 5x headroom for CI variance.
      expect(stopwatch.elapsedMilliseconds, lessThan(250),
          reason: 'analyze() took ${stopwatch.elapsedMilliseconds} ms; '
              'it must not block the scanning loop');
      expect(result.bucket, LuminanceBucket.normal);
    });
  });

  group('LuminanceDetector.analyzeRgba() (JPEG-decoded path)', () {
    test('returns dark for an all-black RGBA buffer', () {
      final rgba = Uint8List.fromList(List<int>.filled(64 * 4, 0));
      final result = LuminanceDetector.analyzeRgba(
        rgbaBytes: rgba,
        width: 8,
        height: 8,
      );
      expect(result.luminance, 0);
      expect(result.bucket, LuminanceBucket.dark);
    });

    test('returns bright for an all-white RGBA buffer', () {
      final rgba = Uint8List.fromList(List<int>.filled(64 * 4, 255));
      final result = LuminanceDetector.analyzeRgba(
        rgbaBytes: rgba,
        width: 8,
        height: 8,
      );
      expect(result.luminance, 255);
      expect(result.bucket, LuminanceBucket.bright);
    });

    test('returns dark for a dim RGBA buffer (~RGB 20,20,20)', () {
      // 100 pixels at RGB(20,20,20) → luma 20, dark.
      final rgba = Uint8List.fromList(
        List<int>.generate(100 * 4, (i) => i % 4 == 3 ? 255 : 20),
      );
      final result = LuminanceDetector.analyzeRgba(
        rgbaBytes: rgba,
        width: 10,
        height: 10,
      );
      expect(result.luminance, lessThan(40));
      expect(result.bucket, LuminanceBucket.dark);
    });

    test('uses BT.601 weights (green contributes more than red/blue)', () {
      // 1 pixel only — width=height=1, grid is 8x8 but the clamp makes
      // every sample land on the only pixel. We set:
      //   R=255, G=0, B=0 → luma 76
      //   R=0,   G=255, B=0 → luma 150
      //   R=0,   G=0,   B=255 → luma 29
      // Green > red > blue, matching the BT.601 coefficients.
      final redPixel = Uint8List.fromList([255, 0, 0, 255]);
      final greenPixel = Uint8List.fromList([0, 255, 0, 255]);
      final bluePixel = Uint8List.fromList([0, 0, 255, 255]);

      final red = LuminanceDetector.analyzeRgba(
        rgbaBytes: redPixel,
        width: 1,
        height: 1,
      );
      final green = LuminanceDetector.analyzeRgba(
        rgbaBytes: greenPixel,
        width: 1,
        height: 1,
      );
      final blue = LuminanceDetector.analyzeRgba(
        rgbaBytes: bluePixel,
        width: 1,
        height: 1,
      );

      expect(red.luminance, 76);
      expect(green.luminance, 150);
      expect(blue.luminance, 29);
      expect(green.luminance, greaterThan(red.luminance));
      expect(red.luminance, greaterThan(blue.luminance));
    });
  });

  group('LuminanceResult.shouldSuggestTorch', () {
    test('true for dark bucket', () {
      const r = LuminanceResult(luminance: 20, bucket: LuminanceBucket.dark);
      expect(r.shouldSuggestTorch, isTrue);
    });
    test('false for normal bucket', () {
      const r = LuminanceResult(luminance: 100, bucket: LuminanceBucket.normal);
      expect(r.shouldSuggestTorch, isFalse);
    });
    test('false for bright bucket', () {
      const r = LuminanceResult(luminance: 220, bucket: LuminanceBucket.bright);
      expect(r.shouldSuggestTorch, isFalse);
    });
  });

  group('TorchController (camera wrapper)', () {
    test('setTorch(true) calls controller.setFlashMode(torch)', () async {
      final fake = _FakeCameraController();
      final tc = TorchController(controller: fake);

      await tc.setTorch(true);

      expect(fake.flashModeCalls, [FlashMode.torch]);
      expect(tc.isOn, isTrue);
    });

    test('setTorch(false) calls controller.setFlashMode(off)', () async {
      final fake = _FakeCameraController();
      final tc = TorchController(controller: fake);
      // First turn it on so the off call is not short-circuited.
      await tc.setTorch(true);
      await tc.setTorch(false);

      expect(fake.flashModeCalls, [FlashMode.torch, FlashMode.off]);
      expect(tc.isOn, isFalse);
    });

    test('setTorch(false) is a no-op when torch is already off (idempotent)',
        () async {
      final fake = _FakeCameraController();
      final tc = TorchController(controller: fake);
      await tc.setTorch(false);
      await tc.setTorch(false); // second call should not call setFlashMode

      expect(fake.flashModeCalls, isEmpty,
          reason: 'Idempotent off→off calls must not spam the camera '
              'plugin with FlashMode.off IPCs.');
    });

    test(
        'setTorch tolerates CameraException (hardware does not support '
        'torch) by leaving isOn false and returning false', () async {
      final fake = _FakeCameraController()..failNextTorch = true;
      final tc = TorchController(controller: fake);

      final ok = await tc.setTorch(true);

      expect(ok, isFalse);
      expect(tc.isOn, isFalse,
          reason: 'A failed torch call must not leave us thinking the '
              'flash is on — the user would never get feedback about the '
              'failed hardware call.');
    });

    test('setTorch(true) is a no-op when torch is already on (idempotent)',
        () async {
      final fake = _FakeCameraController();
      final tc = TorchController(controller: fake);
      await tc.setTorch(true);
      await tc.setTorch(true); // second call should not call setFlashMode

      expect(fake.flashModeCalls, [FlashMode.torch],
          reason: 'Idempotent calls must not spam the camera plugin.');
    });
  });
}

/// Minimal double for [CameraController]. We only need the subset of
/// methods that [TorchController] actually calls. Using a hand-rolled
/// fake (rather than mockito) keeps the test dependency-free and fast.
class _FakeCameraController implements CameraController {
  List<FlashMode> flashModeCalls = [];
  bool failNextTorch = false;

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    flashModeCalls.add(mode);
    if (mode == FlashMode.torch && failNextTorch) {
      failNextTorch = false;
      throw CameraException('torchFailed', 'simulated hardware failure');
    }
  }

  // -------------------------------------------------------------------------
  // Members of CameraController that we don't exercise. Implementing them
  // is mechanical boilerplate — we return neutral defaults.
  // -------------------------------------------------------------------------
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
