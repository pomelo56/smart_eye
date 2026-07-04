import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_result.dart';
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/ocr_service.dart';
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

  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _isAnnouncing = false; // true while announcing a code; pauses scanning
  String? _lastAnnouncedCode;
  String? _lastDetectedPlatform;
  Timer? _scanTimer;
  bool _feedbackBusy = false;
  DateTime? _ocrLogTimer;
  DateTime? _lastBeepTime; // cooldown for distance feedback beeps

  static const _tutorialKey = 'has_seen_tutorial_v4';

  void _log(String msg) {
    _logger.write('INFO', msg);
    if (mounted) {
      setState(() {}); // refresh screen buffer
    }
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

    await _checkFirstLaunch();
    await _initCameraWithRetry();

    _log('=== 启动完成 ===');
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
        // Wait for tutorial to finish before camera starts.
        // Tutorial is ~8 seconds at 1.3x speed; 2s was not enough.
        await Future.delayed(const Duration(seconds: 8));
      } else {
        // Subsequent launches: short confirmation
        await _ttsService.speak('欢迎使用慧眼');
        await Future.delayed(const Duration(seconds: 1));
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
      await _cameraController!.initialize().timeout(const Duration(seconds: 15));
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
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) => _scanFrame());
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
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // Clean up temp file
      try {
        final file = File(image.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      final text = recognizedText.text.trim();
      final hasText = text.isNotEmpty;

      // Always log OCR result every 5 seconds
      if (_ocrLogTimer == null ||
          DateTime.now().difference(_ocrLogTimer!) >
              const Duration(seconds: 5)) {
        _log('OCR: ${hasText ? '${text.length}字 ${text.substring(0, text.length > 50 ? 50 : text.length)}' : '无文字'}');
        _ocrLogTimer = DateTime.now();
      }

      final codes = _ocrService.extractMealCodes(recognizedText.text);

      if (codes.isEmpty) {
        // No codes found but text detected → play scanning prompt.
        if (hasText) {
          _log('codes=[] → 识别中提示');
          await _playScanningPrompt();
        }
      } else {
        // Single or multi-code: find each code's containing block for
        // accurate per-receipt platform detection.
        final results = <ScanResult>[];
        double? minX, minY, maxX, maxY;

        // Compute overall text bounds from all blocks.
        for (final block in recognizedText.blocks) {
          final box = block.boundingBox;
          if (minX == null || box.left < minX) minX = box.left;
          if (minY == null || box.top < minY) minY = box.top;
          if (maxX == null || box.right > maxX) maxX = box.right;
          if (maxY == null || box.bottom > maxY) maxY = box.bottom;
        }
        final textBounds = (minX != null && minY != null && maxX != null && maxY != null)
            ? Rect.fromLTRB(minX, minY, maxX, maxY)
            : Rect.zero;

        // For each code, find its block, position, and platform.
        for (final code in codes) {
          // Find the block containing this code.
          String? blockText;
          Rect? codeBox;
          for (final block in recognizedText.blocks) {
            if (block.text.contains(code) ||
                block.text.contains(code.replaceFirst('#', ''))) {
              codeBox = block.boundingBox;
              blockText = block.text;
              break;
            }
          }
          if (codeBox == null || blockText == null) continue;

          final center = Offset(
            (codeBox.left + codeBox.right) / 2,
            (codeBox.top + codeBox.bottom) / 2,
          );
          final posLabel = computePositionLabel(center, textBounds);
          // Detect platform using ONLY the code's own block text,
          // preventing cross-receipt misidentification.
          final platform = _ocrService.detectPlatform(blockText, nearCode: code);

          results.add(ScanResult(
            code: code,
            platform: platform,
            positionLabel: posLabel,
            center: center,
          ));
        }

        if (results.isEmpty) {
          await _playScanningPrompt();
        } else {
          // Sort by screen position: top-to-bottom, then left-to-right.
          results.sort((a, b) {
            final yDiff = a.center.dy.compareTo(b.center.dy);
            if (yDiff.abs() > 20) return yDiff;
            return a.center.dx.compareTo(b.center.dx);
          });

          if (results.length == 1) {
            // Single code flow.
            final r = results.first;
            final platformLabel = r.platform ?? '未知';
            _log('codes=$codes platform=$platformLabel');
            final confirmed = _ocrService.processFrame(r.code);
            _log('confirmed=$confirmed cool=${_ocrService.isInCooldown(r.code)}');
            if (confirmed != null) {
              _log('识别到取餐码: ${r.code} ($platformLabel)');
              _lastAnnouncedCode = confirmed;
              _lastDetectedPlatform = r.platform;
              await _historyService.add(confirmed);
              _isAnnouncing = true;
              await _ttsService.stop();
              await _ttsService.speak(
                  _ttsService.formatMealCodeWithPlatform(confirmed, r.platform));
              await Future.delayed(const Duration(milliseconds: 3000));
              _isAnnouncing = false;
            }
          } else {
            // Multi-code flow.
            _log('codes=$codes → 多码检测');
            final firstCode = results.first.code;
            final confirmed = _ocrService.processFrame(firstCode);
            if (confirmed != null) {
              for (final r in results.skip(1)) {
                _ocrService.processFrame(r.code);
              }

              final summary = results
                  .map((r) => '${r.code}(${r.platform ?? '?'})${r.positionLabel}')
                  .join(' ');
              _log('多码播报: $summary');

              _lastAnnouncedCode = results.first.code;
              _lastDetectedPlatform = results.first.platform;
              for (final r in results) {
                await _historyService.add(r.code);
              }

              _isAnnouncing = true;
              await _ttsService.stop();
              await _ttsService.speakMultiCode(results);
              final estimatedMs = 1200 + results.length * 4 * 400;
              await Future.delayed(Duration(milliseconds: estimatedMs));
              _isAnnouncing = false;
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

    // Longer cooldown to prevent stacking (1.5s for slow, 1s for fast)
    await Future.delayed(Duration(milliseconds: slow ? 1500 : 1000));
    _feedbackBusy = false;
  }

  Future<void> _replayLast() async {
    _log('手势: 单击重听');
    await _ttsService.stop();
    if (_lastAnnouncedCode != null) {
      await _ttsService.speak(_ttsService
          .formatMealCodeWithPlatform(_lastAnnouncedCode!, _lastDetectedPlatform));
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
    _isAnnouncing = false;
    await _ttsService.speak('没有识别到取餐码，请重新对准小票');
    // Wait for the prompt to finish before scanning resumes.
    await Future.delayed(const Duration(seconds: 3));
  }

  Future<void> _announceHistory() async {
    _log('手势: 上滑历史');
    await _ttsService.stop();
    try {
      final records = await _historyService.getRecent();
      if (records.isEmpty) {
        await _ttsService.speak('没有识别记录');
        return;
      }

      final buffer = StringBuffer('最近识别记录：');
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        buffer.write('第 ${i + 1} 条，取餐码 ${record.code}，${record.timeDescription}');
        if (i < records.length - 1) {
          buffer.write('；');
        }
      }

      await _ttsService.speak(buffer.toString());
    } catch (e) {
      _log('历史错误: $e');
      await _ttsService.speak('历史记录读取失败');
    }
  }

  Future<void> _announceHelp() async {
    _log('手势: 下滑帮助');
    await _ttsService.stop();
    await _ttsService.speak('操作帮助');
  }

  Future<void> _exportLogs() async {
    _log('手势: 双击导出日志');
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
      _initCameraWithRetry();
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
                      width: _cameraController!.value.previewSize?.height ??
                          720,
                      height: _cameraController!.value.previewSize?.width ??
                          1280,
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
                  child: Container(
                    color: Colors.black.withOpacity(0.8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _logger.screenBuffer
                          .map((l) => Text(
                                l,
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 11),
                              ))
                          .toList(),
                    ),
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
