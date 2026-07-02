import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_code.dart';
import '../services/ocr_service.dart';
import '../services/tts_service.dart';

/// Main screen for 慧眼 SmartEye.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late TtsService _ttsService;
  final OcrService _ocrService = OcrService();
  final TextRecognizer _textRecognizer = TextRecognizer();

  bool _isCameraReady = false;
  bool _isProcessing = false;
  String? _lastAnnouncedCode;
  Timer? _scanTimer;
  Timer? _noResultTimer;

  // Debug display
  final List<String> _logs = [];
  final List<MealCode> _history = [];
  static const _historyKey = 'meal_code_history';
  static const _tutorialKey = 'has_seen_tutorial_v3';

  void _log(String msg) {
    debugPrint('[慧眼] $msg');
    if (mounted) {
      setState(() {
        _logs.add('[${DateTime.now().second}] $msg');
        if (_logs.length > 15) _logs.removeAt(0);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _log('initState');
    _initialize();
  }

  Future<void> _initialize() async {
    _log('=== 启动 ===');

    // Step 1: TTS
    _log('Step 1: TTS 初始化...');
    _ttsService = TtsService();
    await _ttsService.initialize();
    _log('TTS: ${_ttsService.isInitialized ? 'OK' : 'FAIL'}');
    _log('语言: ${_ttsService.initStatus}');

    // Step 2: TTS diagnostic - try English first, then Chinese
    _log('Step 2: TTS 诊断...');
    await Future.delayed(const Duration(milliseconds: 500));

    bool englishOk = false;
    bool chineseOk = false;
    if (_ttsService.isInitialized) {
      try {
        await _ttsService.speak('hello');
        englishOk = _ttsService.lastSpeakResult == 1;
        _log('英文: result=${_ttsService.lastSpeakResult}');
      } catch (e) {
        _log('英文错误: $e');
      }

      await Future.delayed(const Duration(seconds: 1));

      try {
        await _ttsService.speak('慧眼已启动');
        chineseOk = _ttsService.lastSpeakResult == 1;
        _log('中文: result=${_ttsService.lastSpeakResult}');
      } catch (e) {
        _log('中文错误: $e');
      }
    }

    // Step 3: History
    _log('Step 3: 加载历史...');
    await _loadHistory();
    _log('历史: ${_history.length} 条');

    // Step 4: Camera (with retry)
    _log('Step 4: 初始化相机...');
    await _initCameraWithRetry();

    _log('=== 启动完成 ===');

    // Step 5: First launch tutorial (always try)
    await _checkFirstLaunch();
  }

  Future<void> _initCameraWithRetry() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      _log('相机尝试 $attempt/3...');
      final ok = await _initCamera();
      if (ok) return;
      _log('相机失败，${attempt < 3 ? '重试...' : '放弃'}');
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  Future<bool> _initCamera() async {
    // Clean up old controller first
    _cameraController?.dispose();
    _cameraController = null;
    if (mounted) setState(() => _isCameraReady = false);

    _log('查询相机...');
    List<CameraDescription>? cameras;
    try {
      cameras = await availableCameras().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _log('ERROR: 查询相机超时');
      return false;
    } catch (e) {
      _log('ERROR: 查询相机: $e');
      return false;
    }

    if (cameras == null || cameras.isEmpty) {
      _log('ERROR: 无可用相机');
      return false;
    }
    _log('找到 ${cameras.length} 个相机');

    final backCamera = cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras!.first,
    );
    _log('选择: ${backCamera.lensDirection}');

    // Use medium resolution for faster initialization
    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _log('CameraController.initialize()...');
    try {
      await _cameraController!.initialize().timeout(const Duration(seconds: 15));
      _log('相机 OK');
      if (mounted) {
        setState(() => _isCameraReady = true);
        _startScanning();
      }
      return true;
    } on TimeoutException {
      _log('TIMEOUT: 相机初始化 15秒');
      _cameraController?.dispose();
      _cameraController = null;
      return false;
    } catch (e) {
      _log('ERROR: 相机: $e');
      _cameraController?.dispose();
      _cameraController = null;
      return false;
    }
  }

  void _startScanning() {
    _log('开始扫描 (每2秒)');
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

      // Clean up temp image file
      try {
        final file = File(image.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      final codes = _ocrService.extractMealCodes(recognizedText.text);
      if (codes.isNotEmpty) {
        final confirmed = _ocrService.processFrame(codes.first);
        if (confirmed != null && !_ocrService.isInCooldown(confirmed)) {
          _log('识别到: $confirmed');
          _ttsService.speak('取餐码是 ${_ttsService.formatMealCode(confirmed)}');
          await _addToHistory(confirmed);
        }
      }
    } catch (e) {
      _log('扫描错误: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _addToHistory(String code) async {
    final entry = MealCode(code: code, recognizedAt: DateTime.now());
    _history.insert(0, entry);
    await _saveHistory();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final validEntries = _history.where((h) {
      return DateTime.now().difference(h.recognizedAt) < const Duration(hours: 24);
    }).toList();
    final storage = validEntries.map((e) => e.toStorageString()).toList();
    await prefs.setStringList(_historyKey, storage);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final storage = prefs.getStringList(_historyKey) ?? [];
    final now = DateTime.now();
    _history.addAll(
      storage.map(MealCode.fromStorageString).where((e) =>
          e != null &&
          now.difference(e.recognizedAt) < const Duration(hours: 24)).cast<MealCode>(),
    );
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

  Future<void> _replayLast() async {
    _log('手势: 单击重听');
    if (_lastAnnouncedCode != null) {
      await _ttsService
          .speak('取餐码是 ${_ttsService.formatMealCode(_lastAnnouncedCode!)}');
    } else {
      await _ttsService.speak('暂无取餐码，请对准小票等待识别');
    }
  }

  Future<void> _restartScan() async {
    _log('手势: 三击重识');
    _ocrService.processFrame(null);
    _lastAnnouncedCode = null;
    await _ttsService.speak('已重新开始识别，请对准外卖袋上的小票');
  }

  Future<void> _announceHistory() async {
    _log('手势: 上滑历史');
    if (_history.isEmpty) {
      await _ttsService.speak('暂无历史记录');
      return;
    }
    final items = _history.take(5).toList();
    final buffer = StringBuffer('最近识别到 ${items.length} 个取餐码：');
    for (var i = 0; i < items.length; i++) {
      buffer.write(
          '${_ttsService.formatMealCode(items[i].code)}，${items[i].timeDescription}');
      if (i < items.length - 1) buffer.write('；');
    }
    await _ttsService.speak(buffer.toString());
  }

  Future<void> _announceHelp() async {
    _log('手势: 下滑帮助');
    await _ttsService.speak(
      '操作帮助。单击屏幕重听上一次取餐码。'
      '三击屏幕重新开始识别。向上滑动查看最近历史记录。'
      '向下滑动播报此帮助信息。',
    );
  }

  int _tapCount = 0;
  Timer? _tapTimer;

  void _handleTap() {
    _tapCount++;
    _tapTimer?.cancel();
    // Use 600ms window for better accessibility (was 300ms)
    _tapTimer = Timer(const Duration(milliseconds: 600), () {
      if (_tapCount == 1) {
        _replayLast();
      } else if (_tapCount >= 3) {
        _restartScan();
      } else if (_tapCount == 2) {
        // Double tap: announce help
        _announceHelp();
      }
      _tapCount = 0;
    });
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
    _noResultTimer?.cancel();
    _tapTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200) {
          _announceHistory(); // Swipe up
        } else if (details.primaryVelocity! > 200) {
          _announceHelp(); // Swipe down
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Camera preview (full screen when ready)
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

            // Layer 2: Debug log panel (always visible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.85),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '慧眼 调试模式',
                        style: TextStyle(
                            color: Colors.yellow,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ..._logs.map((l) => Text(
                            l,
                            style: const TextStyle(
                                color: Colors.greenAccent, fontSize: 12),
                          )),
                      if (_logs.isEmpty)
                        const Text('等待日志...',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
