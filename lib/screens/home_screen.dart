import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_result.dart';
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/ocr_service.dart';
import '../services/permission_service.dart';
import '../services/tts_service.dart';

/// Main screen for the SmartEye MVP.
///
/// Provides a full-screen touch surface with camera preview, voice feedback,
/// and simple gestures designed for blind/low-vision users.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late TtsService _ttsService;
  late HistoryService _historyService;
  final OcrService _ocrService = OcrService();
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);
  final FileLogger _logger = FileLogger.instance;
  final PermissionService _permissionService = PermissionService();

  /// True if the user has permanently denied camera permission and the
  /// only path forward is the system settings page. When this is set,
  /// we stop retrying camera initialization and surface the "permanently
  /// denied" prompt on every entry to the screen.
  bool _permissionPermanentlyDenied = false;

  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _isAnnouncing = false; // true while announcing a code; pauses scanning
  String? _lastAnnouncedCode;
  String? _lastDetectedPlatform;
  String? _lastCodePosition; // remembers where the code was last seen
  Timer? _scanTimer;
  bool _feedbackBusy = false;
  DateTime? _ocrLogTimer;
  DateTime? _lastBeepTime; // cooldown for distance feedback beeps
  DateTime? _lastGuidanceTime; // cooldown for direction guidance
  DateTime? _lastTakeoutPromptTime; // cooldown for "发现外卖" prompt

  /// Cross-frame code cache: codes seen in the last [_codeCacheWindow].
  /// When a receipt is upside down, OCR may only detect one code per frame.
  /// We merge codes across frames so multi-code scenarios still work.
  final Map<String, _CachedCode> _codeCache = {};
  static const _codeCacheWindow = Duration(seconds: 3);

  static const _tutorialKey = 'has_seen_tutorial_v4';

  void _log(String msg) {
    _logger.write('INFO', msg);
    // The screen overlay listens to FileLogger.screenBufferNotifier,
    // so no setState is needed here.
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _logger.initialize();
    _log('=== 慧眼启动 ===');

    _ttsService = TtsService();
    await _ttsService.initialize();
    _log('语音: ${_ttsService.isInitialized ? '就绪' : '未就绪'} '
        '引擎=${_ttsService.engineName}');

    final prefs = await SharedPreferences.getInstance();
    _historyService = HistoryService(prefs: prefs);

    // Camera permission check must run BEFORE the first-launch tutorial
    // so a permanently denied user hears the "open settings" prompt
    // instead of a tutorial they can't act on. The tutorial only
    // proceeds if the camera is eventually usable.
    final hasPermission = await _ensureCameraPermission();
    if (!hasPermission) {
      _log('启动中止: 无摄像头权限');
      _log('=== 启动完成 (无权限) ===');
      return;
    }

    await _checkFirstLaunch();
    await _initCameraWithRetry();

    _log('=== 启动完成 ===');
  }

  /// Ensures the camera permission is granted before the rest of the app
  /// starts talking to the camera.
  ///
  /// Returns true if permission is granted (or was just granted), false
  /// if the user denied it. When denied, the screen speaks the
  /// appropriate prompt and, if the denial is permanent, opens the
  /// system settings page.
  ///
  /// v0.7.1: this is the fix for the silent startup failure where the
  /// app would log "camera not available" repeatedly with no audio
  /// feedback. Visually impaired users would think the app was broken.
  Future<bool> _ensureCameraPermission() async {
    var status = await _permissionService.checkCameraPermission();
    _log('初始权限状态: $status');

    if (status == PermissionStatus.granted) {
      return true;
    }

    if (status == PermissionStatus.unknown) {
      // The MethodChannel wasn't wired up (e.g. running on a host with
      // no MainActivity). Fall back to asking the system dialog anyway
      // — if it doesn't exist, the request will be a no-op and we'll
      // fail through to the camera retry loop, which already handles
      // CameraException gracefully.
      status = await _permissionService.requestCameraPermission();
      _log('权限请求 (fallback): $status');
    }

    if (status == PermissionStatus.granted) {
      return true;
    }

    // Permission is denied. Speak the prompt and decide the recovery path.
    if (status == PermissionStatus.permanentlyDenied) {
      _permissionPermanentlyDenied = true;
      await _ttsService.stop();
      await _ttsService.speakCameraPermissionPermanentlyDenied();
      // Try to open settings immediately. If the user grants the
      // permission and returns to the app, [didChangeAppLifecycleState]
      // will retry the camera.
      final opened = await _permissionService.openAppSettings();
      _log('永久拒绝: 跳转设置=$opened');
    } else {
      // First-time or normal denial: ask the system once, then guide.
      await _ttsService.stop();
      await _ttsService.speakCameraPermissionDenied();
      status = await _permissionService.requestCameraPermission();
      _log('权限请求结果: $status');

      if (status == PermissionStatus.granted) {
        return true;
      }
      if (status == PermissionStatus.permanentlyDenied) {
        _permissionPermanentlyDenied = true;
        await _ttsService.speakCameraPermissionPermanentlyDenied();
        await _permissionService.openAppSettings();
      }
    }

    return false;
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeen = prefs.getBool(_tutorialKey) ?? false;
      if (!hasSeen) {
        // First launch: full tutorial
        await Future.delayed(const Duration(milliseconds: 500));
        await _ttsService.speak(
          '欢迎使用慧眼。将手机摄像头对准外卖袋上的打印小票，'
          '应用会自动识别取餐码并播报。单击屏幕重听，三击重新识别，'
          '向上滑动查看历史记录，向下滑动获取操作帮助。',
        );
        await prefs.setBool(_tutorialKey, true);
        _log('教程已播报');
      } else {
        // Subsequent launches: short confirmation
        await _ttsService.speak('欢迎使用慧眼');
      }
    } catch (e) {
      _log('教程错误: $e');
    }
  }

  Future<void> _initCameraWithRetry() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      _log('相机尝试 $attempt/3');
      final ok = await _initCamera();
      if (ok) return;
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    _log('相机不可用');

    // v0.7.1: when the camera cannot be initialized, check whether the
    // cause is a missing permission. If so, surface a clear voice
    // prompt. Without this, the app used to log "camera unavailable"
    // and go silent, leaving the user with no audio feedback at all.
    final status = await _permissionService.checkCameraPermission();
    if (status == PermissionStatus.denied) {
      await _ttsService.speakCameraPermissionDenied();
    } else if (status == PermissionStatus.permanentlyDenied) {
      _permissionPermanentlyDenied = true;
      await _ttsService.speakCameraPermissionPermanentlyDenied();
    }
  }

  Future<bool> _initCamera() async {
    _cameraController?.dispose();
    _cameraController = null;
    if (mounted) setState(() => _isCameraReady = false);

    List<CameraDescription>? cameras;
    try {
      cameras = await availableCameras().timeout(const Duration(seconds: 10));
    } catch (e) {
      _log('相机查询失败: $e');
      return false;
    }

    if (cameras.isEmpty) {
      _log('无可用相机');
      return false;
    }
    _log('找到 ${cameras.length} 个相机');

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras!.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!
          .initialize()
          .timeout(const Duration(seconds: 15));
      _log('相机就绪 (${backCamera.lensDirection})');
      if (mounted) {
        setState(() => _isCameraReady = true);
        _startScanning();
      }
      return true;
    } catch (e) {
      _log('相机初始化失败: $e');
      _cameraController?.dispose();
      _cameraController = null;
      return false;
    }
  }

  void _startScanning() {
    _scanTimer?.cancel();
    _scanTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _scanFrame());
    _log('扫描已启动 (每2秒)');
  }

  Future<void> _scanFrame() async {
    // Skip scanning while announcing to prevent audio overlap.
    if (_isAnnouncing ||
        _isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _isProcessing = true;
    try {
      final image = await _cameraController!.takePicture();

      // Read actual image dimensions for accurate position calculation.
      // The captured image may be in sensor-native (landscape) orientation
      // or already rotated to portrait, depending on the device.
      int imgW = 720, imgH = 1280;
      try {
        final bytes = await File(image.path).readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        imgW = descriptor.width;
        imgH = descriptor.height;
        buffer.dispose();
        descriptor.dispose();
      } catch (_) {
        // Fallback to previewSize if descriptor fails
      }

      // Recognize both the original and 180°-rotated image, then merge.
      // Visually impaired users cannot rotate receipts, so the app must
      // handle both orientations automatically.
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // Recognize 180°-rotated copy. Block coordinates in the result are in
      // the rotated image space; we'll transform them back later.
      final rotatedText = await _recognizeRotated(image.path, 180);

      // Clean up temp file
      try {
        final file = File(image.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      // Merge both recognition results into a single text + block list.
      // Block coordinates from rotated text need to be transformed back to
      // the original image space.
      final allBlocks = <_OrientedBlock>[
        ...recognizedText.blocks.map((b) => _OrientedBlock(b, false)),
        ...rotatedText.blocks.map((b) => _OrientedBlock(b, true)),
      ];
      final combinedText = allBlocks.map((b) => b.block.text).join('\n');
      final hasText = combinedText.trim().isNotEmpty;

      // Always log OCR result every 5 seconds
      if (_ocrLogTimer == null ||
          DateTime.now().difference(_ocrLogTimer!) >
              const Duration(seconds: 5)) {
        final preview = combinedText.length > 50
            ? combinedText.substring(0, 50)
            : combinedText;
        _log('OCR: ${hasText ? '${combinedText.length}字 $preview' : '无文字'}');
        _ocrLogTimer = DateTime.now();
      }

      final codes = _ocrService.extractMealCodes(combinedText);

      if (codes.isEmpty) {
        // No codes found but text detected → distinguish "found the
        // delivery platform but no code yet" from "just random text".
        if (hasText) {
          if (_ocrService.hasPlatformKeyword(combinedText)) {
            _log('platform keyword detected → 发现外卖提示');
            await _playDetectedTakeoutPrompt();
          } else {
            _log('no platform keyword → 识别中提示');
            await _playScanningPrompt();
          }
        } else {
          // No text at all → receipt likely out of frame.
          // Guide the user back based on last known position.
          await _playDirectionGuidance();
        }
      } else {
        // Single or multi-code: find each code's containing block for
        // accurate per-receipt platform detection.
        final results = <ScanResult>[];

        // Use the full image frame as position reference.
        // ML Kit's InputImage.fromFilePath reads EXIF rotation metadata and
        // internally rotates the image to upright (portrait) orientation.
        // Therefore bounding boxes are ALREADY in upright coordinate space —
        // no manual transformation needed. We just need the upright dimensions.
        final isLandscapeRaw = imgW > imgH;
        // Upright (portrait) dimensions after EXIF rotation is applied.
        final uprightW = isLandscapeRaw ? imgH.toDouble() : imgW.toDouble();
        final uprightH = isLandscapeRaw ? imgW.toDouble() : imgH.toDouble();
        final imageBounds = Rect.fromLTWH(0, 0, uprightW, uprightH);

        // For each code, find its block, position, and platform.
        for (final code in codes) {
          // Find the block containing this code.
          // Use multi-pass matching to avoid false matches:
          //   1. Exact "#18" match (most reliable)
          //   2. Block contains "#" AND the digits (e.g. "# 18")
          //   3. Fallback: digits only (least reliable, may match dates/prices)
          String? blockText;
          Rect? codeBox;

          // Pass 1: exact match (e.g. block contains "#18")
          for (final ob in allBlocks) {
            if (ob.block.text.contains(code)) {
              codeBox = ob.transformedBox(uprightW, uprightH);
              blockText = ob.block.text;
              break;
            }
          }

          // Pass 2: block has "#" and the digits separately
          if (codeBox == null) {
            final digits = code.replaceFirst('#', '');
            for (final ob in allBlocks) {
              if (ob.block.text.contains('#') &&
                  ob.block.text.contains(digits)) {
                codeBox = ob.transformedBox(uprightW, uprightH);
                blockText = ob.block.text;
                break;
              }
            }
          }

          // Pass 3: fallback — digits only
          if (codeBox == null) {
            final digits = code.replaceFirst('#', '');
            for (final ob in allBlocks) {
              if (ob.block.text.contains(digits)) {
                codeBox = ob.transformedBox(uprightW, uprightH);
                blockText = ob.block.text;
                break;
              }
            }
          }

          if (codeBox == null || blockText == null) continue;

          // Bounding box is already in upright (portrait) coordinate space.
          // Use it directly — no transformation.
          final center = Offset(
            (codeBox.left + codeBox.right) / 2,
            (codeBox.top + codeBox.bottom) / 2,
          );
          final posLabel = computePositionLabel(center, imageBounds);
          _lastCodePosition = posLabel; // remember for direction guidance
          _log(
              '位置调试: code=$code center=(${center.dx.toInt()},${center.dy.toInt()}) '
              'upright=${uprightW.toInt()}x${uprightH.toInt()} '
              'rawImg=${imgW}x$imgH posLabel=$posLabel');
          // Detect platform using ONLY the code's own block text,
          // preventing cross-receipt misidentification.
          final platform =
              _ocrService.detectPlatform(blockText, nearCode: code);

          results.add(ScanResult(
            code: code,
            platform: platform,
            positionLabel: posLabel,
            center: center,
          ));
        }

        // --- Cross-frame code merging ---
        // When a receipt is upside down, OCR may only detect one code per
        // frame. We cache detected codes for [_codeCacheWindow] and merge
        // them with the current frame so multi-code scenarios still work.
        final now = DateTime.now();

        // Purge expired entries.
        _codeCache.removeWhere((key, cached) =>
            now.difference(cached.timestamp) > _codeCacheWindow);

        // Add/update current frame's codes into the cache.
        for (final r in results) {
          _codeCache[r.code] = _CachedCode(
            code: r.code,
            platform: r.platform,
            positionLabel: r.positionLabel,
            center: r.center,
            timestamp: now,
          );
        }

        // Build merged results from cache (current frame + recent frames),
        // converted to ScanResult for downstream compatibility.
        final mergedResults = _codeCache.values
            .map((c) => ScanResult(
                  code: c.code,
                  platform: c.platform,
                  positionLabel: c.positionLabel,
                  center: c.center,
                ))
            .toList()
          ..sort((a, b) {
            final yDiff = a.center.dy.compareTo(b.center.dy);
            if (yDiff.abs() > 20) return yDiff;
            return a.center.dx.compareTo(b.center.dx);
          });

        // Use merged results if there are more codes than the current frame.
        final effectiveResults =
            mergedResults.length > results.length ? mergedResults : results;

        if (effectiveResults.isEmpty) {
          await _playScanningPrompt();
        } else {
          // effectiveResults is already sorted (from cache merge or above).
          // Re-sort to be safe.
          effectiveResults.sort((a, b) {
            final yDiff = a.center.dy.compareTo(b.center.dy);
            if (yDiff.abs() > 20) return yDiff;
            return a.center.dx.compareTo(b.center.dx);
          });

          if (effectiveResults.length == 1) {
            // Single code flow.
            final r = effectiveResults.first;
            final platformLabel = r.platform ?? '未知';
            _log('codes=$codes platform=$platformLabel');
            final confirmed = _ocrService.processFrame(r.code);
            _log(
                'confirmed=$confirmed cool=${_ocrService.isInCooldown(r.code)}');
            if (confirmed != null) {
              _log('识别到取餐码: ${r.code} ($platformLabel) ${r.positionLabel}');
              _lastAnnouncedCode = confirmed;
              _lastDetectedPlatform = r.platform;
              _lastCodePosition = r.positionLabel;
              await _historyService.add(confirmed, platform: r.platform);
              _isAnnouncing = true;
              await _ttsService.stop();
              await _ttsService.speakSingleCodeWithPosition(
                  confirmed, r.platform, r.positionLabel);
              _isAnnouncing = false;
            }
          } else {
            // Multi-code flow.
            _log(
                'codes=$codes effective=${effectiveResults.map((r) => r.code).toList()} → 多码检测');
            // Check if ANY code is new (not in cooldown).
            final hasNewCode =
                effectiveResults.any((r) => !_ocrService.isInCooldown(r.code));
            if (hasNewCode) {
              for (final r in effectiveResults) {
                _ocrService.processFrame(r.code);
              }

              final summary = effectiveResults
                  .map((r) =>
                      '${r.code}(${r.platform ?? '?'})${r.positionLabel}')
                  .join(' ');
              _log('多码播报: $summary');

              _lastAnnouncedCode = effectiveResults.first.code;
              _lastDetectedPlatform = effectiveResults.first.platform;
              _lastCodePosition = effectiveResults.first.positionLabel;
              for (final r in effectiveResults) {
                await _historyService.add(r.code, platform: r.platform);
              }

              _isAnnouncing = true;
              await _ttsService.stop();
              await _ttsService.speakMultiCode(effectiveResults);
              _isAnnouncing = false;
            } else {
              _log('多码: 所有码均在冷却中，跳过');
            }
          }
        }
      }
    } catch (e) {
      _log('扫描错误: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Plays the "识别中，手机请稳一些" prompt with cooldown.
  Future<void> _playScanningPrompt() async {
    final now = DateTime.now();
    if (_lastBeepTime != null &&
        now.difference(_lastBeepTime!) < const Duration(seconds: 8)) {
      return;
    }
    _lastBeepTime = now;
    await _playDistanceFeedback(slow: true);
    await _ttsService.speakScanning();
  }

  /// Plays the "发现外卖，识别中，手机请稳一些" prompt with cooldown.
  ///
  /// Triggered when a delivery platform keyword (e.g. 美团外卖, 饿了么) is
  /// detected in the frame but no pickup code has been recognized yet.
  /// Has a 5-second cooldown to prevent the prompt from playing every
  /// scan cycle.
  Future<void> _playDetectedTakeoutPrompt() async {
    if (_feedbackBusy || _isAnnouncing) return;

    final now = DateTime.now();
    if (_lastTakeoutPromptTime != null &&
        now.difference(_lastTakeoutPromptTime!) < const Duration(seconds: 5)) {
      return;
    }
    _lastTakeoutPromptTime = now;

    _feedbackBusy = true;
    await _ttsService.stop();
    await _ttsService.speakDetectedTakeout();
    _feedbackBusy = false;
  }

  /// Plays direction guidance when the receipt is out of frame.
  ///
  /// Uses the last known position of the code to tell the user which
  /// direction to move the phone. Has a 5-second cooldown to avoid spam.
  Future<void> _playDirectionGuidance() async {
    if (_feedbackBusy || _isAnnouncing) return;

    final now = DateTime.now();
    if (_lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!) < const Duration(seconds: 5)) {
      return;
    }
    _lastGuidanceTime = now;

    _feedbackBusy = true;
    await _ttsService.stop();

    final clips = <String>['assets/audio/not_in_frame.mp3'];

    // Build direction clips based on last known position.
    final pos = _lastCodePosition;
    if (pos != null) {
      clips.add('assets/audio/move.mp3');
      // Map position label to direction audio.
      final dirClip = _positionToDirectionClip(pos);
      if (dirClip != null) clips.add(dirClip);
      clips.add('assets/audio/pian.mp3');
    }

    _log('方向引导: 小票不在画面中, 上次位置=$pos');
    await _ttsService.speakAudioClips(clips);
    _feedbackBusy = false;
  }

  /// Maps a position label (e.g. "左下") to a direction audio clip.
  String? _positionToDirectionClip(String pos) {
    switch (pos) {
      case '左上':
        return 'assets/audio/up.mp3'; // simplified: guide to upper area
      case '右上':
        return 'assets/audio/up.mp3';
      case '左下':
        return 'assets/audio/down.mp3';
      case '右下':
        return 'assets/audio/down.mp3';
      case '左侧':
        return 'assets/audio/left.mp3';
      case '右侧':
        return 'assets/audio/right.mp3';
      case '上方':
        return 'assets/audio/up.mp3';
      case '下方':
        return 'assets/audio/down.mp3';
      case '中间':
        return null; // no specific direction needed
      default:
        return null;
    }
  }

  Future<void> _playDistanceFeedback({required bool slow}) async {
    if (_feedbackBusy) return;
    // Cooldown: at most one beep per 8 seconds to avoid audio spam
    // when the phone is unsteady.
    final now = DateTime.now();
    if (_lastBeepTime != null &&
        now.difference(_lastBeepTime!) < const Duration(seconds: 8)) {
      return;
    }
    _feedbackBusy = true;
    _lastBeepTime = now;

    // Stop any ongoing playback before playing new feedback
    await _ttsService.stop();

    final code = slow ? 'beep_slow' : 'beep_fast';
    await _ttsService.speak(code);
    _feedbackBusy = false;
  }

  /// Recognizes text in a rotated copy of the given image.
  ///
  /// Used for 180°-rotated receipts that ML Kit can't read normally. Returns
  /// an empty [RecognizedText] if the rotation fails for any reason (e.g. out
  /// of memory, unsupported file format).
  Future<RecognizedText> _recognizeRotated(
      String imagePath, int rotationDeg) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final srcW = src.width;
      final srcH = src.height;
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();

      // Rotate 180°: dstW == srcW, dstH == srcH
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(srcW.toDouble(), srcH.toDouble());
      canvas.rotate(rotationDeg * 3.14159265358979 / 180);
      canvas.drawImage(src, Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(srcW, srcH);
      picture.dispose();
      src.dispose();

      // Encode to PNG and run ML Kit on the bytes.
      final byteData = await rotated.toByteData(format: ui.ImageByteFormat.png);
      rotated.dispose();
      if (byteData == null) {
        return RecognizedText(text: '', blocks: []);
      }

      // Write to a temp file so InputImage.fromFilePath can read it (some
      // Android versions don't support raw byte input images for ML Kit).
      final tmp = File('$imagePath.rotated.png');
      await tmp.writeAsBytes(byteData.buffer.asUint8List());
      final result =
          await _textRecognizer.processImage(InputImage.fromFilePath(tmp.path));
      try {
        await tmp.delete();
      } catch (_) {}
      return result;
    } catch (e) {
      _log('旋转识别失败: $e');
      return RecognizedText(text: '', blocks: []);
    }
  }

  Future<void> _replayLast() async {
    _log('手势: 单击重听');
    await _ttsService.stop();
    if (_lastAnnouncedCode != null) {
      await _ttsService.speakSingleCodeWithPosition(
          _lastAnnouncedCode!, _lastDetectedPlatform, _lastCodePosition);
    } else {
      await _ttsService.speak('没有识别到取餐码');
    }
  }

  Future<void> _restartScan() async {
    _log('手势: 三击重新识别');
    await _ttsService.stop();
    _ocrService.reset();
    _lastAnnouncedCode = null;
    _lastDetectedPlatform = null;
    _lastCodePosition = null;
    _isAnnouncing = false;
    await _ttsService.speak('没有识别到取餐码，请重新对准小票');
  }

  Future<void> _announceHistory() async {
    _log('手势: 上滑历史');
    await _ttsService.stop();
    try {
      final records = await _historyService.getRecent();
      if (records.isEmpty) {
        await _ttsService.speakNoHistory();
        return;
      }
      await _ttsService.speakHistory(records);
    } catch (e) {
      _log('历史错误: $e');
    }
  }

  Future<void> _announceHelp() async {
    _log('手势: 下滑帮助');
    await _ttsService.stop();
    await _ttsService.speak('操作帮助');
  }

  Future<void> _exportLogs() async {
    _log('手势: 双击导出日志');
    // v0.7.1: if the camera never came up because permission was
    // permanently denied, a double-tap (which would normally export
    // logs) should re-surface the permission prompt instead. Without
    // this, the user has no audio feedback that the app is in a
    // permission-denied state — they would just hear "日志导出成功"
    // even though the camera is dead.
    if (_permissionPermanentlyDenied) {
      await _ttsService.speakCameraPermissionPermanentlyDenied();
      return;
    }
    final path = await _logger.exportToDownloads();
    if (path != null) {
      await _ttsService.speak('日志已导出到下载目录');
      _log('日志导出: $path');
    } else {
      await _ttsService.speak('日志导出失败');
      _log('日志导出失败');
    }
  }

  int _tapCount = 0;
  Timer? _tapTimer;

  void _handleTap() {
    _tapCount++;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 600), () {
      if (_tapCount == 1) {
        _replayLast();
      } else if (_tapCount == 2) {
        _exportLogs();
      } else if (_tapCount >= 3) {
        _restartScan();
      }
      _tapCount = 0;
    });
  }

  void _handleVerticalDrag(DragUpdateDetails details) {
    // Ignore small accidental movements.
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null) return;

    if (velocity < -800) {
      _announceHistory();
    } else if (velocity > 800) {
      _announceHelp();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _scanTimer?.cancel();
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _log('应用恢复前台');
      // v0.7.1: if the user came back from the system settings page
      // (where they just granted camera permission), re-check the
      // permission and reinitialize the camera. The previous code
      // unconditionally called _initCameraWithRetry, which would
      // re-enter the failure loop if the permission was still denied.
      _onResumedFromBackground();
    }
  }

  /// Handler for the app returning to the foreground.
  ///
  /// The two cases we care about are:
  /// 1. The user just granted camera permission in the system settings
  ///    page (after a permanent denial). In this case we want to clear
  ///    the [_permissionPermanentlyDenied] flag and retry the camera.
  /// 2. The user briefly switched apps. The camera should be re-opened
  ///    exactly as before.
  Future<void> _onResumedFromBackground() async {
    if (_permissionPermanentlyDenied) {
      final status = await _permissionService.checkCameraPermission();
      _log('恢复后权限状态: $status');
      if (status == PermissionStatus.granted) {
        _permissionPermanentlyDenied = false;
        _log('权限恢复，重新初始化相机');
        await _initCameraWithRetry();
      } else {
        // Still denied. Re-surface the prompt so the user knows what
        // to do. We avoid opening settings again automatically, because
        // a quick app switch should not bounce the user out of their
        // current task.
        await _ttsService.stop();
        await _ttsService.speakCameraPermissionPermanentlyDenied();
      }
    } else {
      await _initCameraWithRetry();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _tapTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
    _textRecognizer.close();
    _logger.write('INFO', '应用关闭');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '慧眼主界面，全屏触摸区域。单击重听，双击导出日志，三击重新识别，向上滑动播报历史记录，向下滑动播报操作帮助。',
      child: GestureDetector(
        onTap: _handleTap,
        onVerticalDragUpdate: _handleVerticalDrag,
        onVerticalDragEnd: _handleVerticalDragEnd,
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview.
              if (_isCameraReady && _cameraController != null)
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width:
                          _cameraController!.value.previewSize?.height ?? 720,
                      height:
                          _cameraController!.value.previewSize?.width ?? 1280,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),

              // Log overlay.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: _logger.screenBufferNotifier,
                    builder: (context, buffer, _) {
                      return Container(
                        color: Colors.black.withOpacity(0.8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: buffer
                              .map((l) => Text(
                                    l,
                                    style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 11),
                                  ))
                              .toList(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A code cached from a recent frame, used for cross-frame merging.
class _CachedCode {
  final String code;
  final String? platform;
  final String positionLabel;
  final Offset center;
  final DateTime timestamp;

  _CachedCode({
    required this.code,
    required this.platform,
    required this.positionLabel,
    required this.center,
    required this.timestamp,
  });
}

/// A recognized text block tagged with whether it came from a rotated image.
///
/// For rotated images, bounding box coordinates are in the rotated coordinate
/// space. [transformedBox] maps them back to the original (upright) space so
/// downstream position logic works uniformly.
class _OrientedBlock {
  final TextBlock block;
  final bool rotated;

  _OrientedBlock(this.block, this.rotated);

  /// Returns the bounding box in the original (upright) image coordinate space.
  ///
  /// [uprightW] and [uprightH] are the dimensions of the upright image.
  Rect transformedBox(double uprightW, double uprightH) {
    if (!rotated) return block.boundingBox;
    // 180° rotation: (x, y) → (W - x, H - y)
    // So the original-space point is (rotW - x, rotH - y).
    // The bounding box in original space is therefore:
    //   left = uprightW - box.right
    //   top = uprightH - box.bottom
    //   right = uprightW - box.left
    //   bottom = uprightH - box.top
    final b = block.boundingBox;
    return Rect.fromLTRB(
      uprightW - b.right,
      uprightH - b.bottom,
      uprightW - b.left,
      uprightH - b.top,
    );
  }
}
