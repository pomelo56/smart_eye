import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/history_service.dart';
import '../services/ocr_service.dart';
import '../services/tts_service.dart';

/// Main screen for the SmartEye MVP.
///
/// Provides a full-screen touch surface with camera preview, voice feedback,
/// and simple gestures designed for blind/low-vision users.
class HomeScreen extends StatefulWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late TtsService _ttsService;
  late HistoryService _historyService;
  final OcrService _ocrService = OcrService();
  final TextRecognizer _textRecognizer = TextRecognizer();

  bool _isCameraReady = false;
  bool _isProcessing = false;
  String? _lastAnnouncedCode;
  Timer? _scanTimer;
  bool _feedbackBusy = false;

  // Tiny debug log for field diagnostics.
  final List<String> _logs = [];
  static const _tutorialKey = 'has_seen_tutorial_v4';

  void _log(String msg) {
    debugPrint('[慧眼] $msg');
    if (mounted) {
      setState(() {
        _logs.add('[${DateTime.now().second}] $msg');
        if (_logs.length > 6) _logs.removeAt(0);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    _log('启动');

    _ttsService = TtsService();
    await _ttsService.initialize();
    _log('语音: ${_ttsService.isInitialized ? '就绪' : '未就绪'}');

    final prefs = await SharedPreferences.getInstance();
    _historyService = HistoryService(prefs: prefs);

    // Audio-first: play a startup chirp so the user knows the app is alive.
    await _ttsService.speak('欢迎使用慧眼');

    await _checkFirstLaunch();
    await _initCameraWithRetry();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeen = prefs.getBool(_tutorialKey) ?? false;
      if (!hasSeen) {
        await Future.delayed(const Duration(seconds: 1));
        await _ttsService.speak(
          '欢迎使用慧眼。将手机摄像头对准外卖袋上的打印小票，'
          '应用会自动识别取餐码并播报。单击屏幕重听，三击重新识别，'
          '向上滑动查看历史记录，向下滑动获取操作帮助。',
        );
        await prefs.setBool(_tutorialKey, true);
        _log('教程已播报');
      }
    } catch (e) {
      _log('教程错误: $e');
    }
  }

  Future<void> _initCameraWithRetry() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      _log('相机 $attempt/3');
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
      _log('相机查询失败');
      return false;
    }

    if (cameras.isEmpty) {
      _log('无相机');
      return false;
    }

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras!.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize().timeout(const Duration(seconds: 15));
      _log('相机就绪');
      if (mounted) {
        setState(() => _isCameraReady = true);
        _startScanning();
      }
      return true;
    } catch (e) {
      _cameraController?.dispose();
      _cameraController = null;
      return false;
    }
  }

  void _startScanning() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) => _scanFrame());
  }

  Future<void> _scanFrame() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _isProcessing = true;
    try {
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      try {
        final file = File(image.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      final hasText = recognizedText.text.trim().isNotEmpty;
      if (hasText) {
        await _playDistanceFeedback(slow: true);
      }

      final codes = _ocrService.extractMealCodes(recognizedText.text);
      if (codes.isNotEmpty) {
        await _playDistanceFeedback(slow: false);

        final confirmed = _ocrService.processFrame(codes.first);
        if (confirmed != null && !_ocrService.isInCooldown(confirmed)) {
          _log('识别: $confirmed');
          _lastAnnouncedCode = confirmed;
          await _historyService.add(confirmed);
          await _ttsService
              .speak('取餐码是 ${_ttsService.formatMealCode(confirmed)}');
        }
      }
    } catch (e) {
      _log('扫描错误');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _playDistanceFeedback({required bool slow}) async {
    if (_feedbackBusy) return;
    _feedbackBusy = true;
    final code = slow ? 'beep_slow' : 'beep_fast';
    await _ttsService.speak(code);
    // Small lock to prevent feedback spamming.
    await Future.delayed(const Duration(milliseconds: 300));
    _feedbackBusy = false;
  }

  Future<void> _replayLast() async {
    _log('重听');
    if (_lastAnnouncedCode != null) {
      await _ttsService
          .speak('取餐码是 ${_ttsService.formatMealCode(_lastAnnouncedCode!)}');
    } else {
      // Demo utterance for quick validation.
      await _ttsService.speak('取餐码是 井 15');
    }
  }

  Future<void> _restartScan() async {
    _log('重新识别');
    _ocrService.processFrame(null);
    _lastAnnouncedCode = null;
    await _ttsService.speak('没有识别到取餐码，请重新对准小票');
  }

  Future<void> _announceHistory() async {
    _log('历史');
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
    _log('帮助');
    await _ttsService.speak('操作帮助');
  }

  int _tapCount = 0;
  Timer? _tapTimer;

  void _handleTap() {
    _tapCount++;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 600), () {
      if (_tapCount == 1) {
        _replayLast();
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
      // Upward swipe
      _announceHistory();
    } else if (velocity > 800) {
      // Downward swipe
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '慧眼主界面，全屏触摸区域。单击重听，三击重新识别，向上滑动播报历史记录，向下滑动播报操作帮助。',
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
              // Optional camera preview.
              if (_isCameraReady && _cameraController != null)
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize?.height ?? 720,
                      height: _cameraController!.value.previewSize?.width ?? 1280,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),

              // Minimal log overlay.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _logs
                          .map((l) => Text(
                                l,
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 12),
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
