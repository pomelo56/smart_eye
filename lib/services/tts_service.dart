import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/scan_result.dart';
import 'audio_service.dart';

/// Voice feedback service.
///
/// The MVP relies on pre-recorded audio assets played through MediaPlayer,
/// because OPPO/ColorOS devices do not expose a bindable system TTS engine to
/// third-party Flutter apps even though the same engine works in Settings.
///
/// Public API is kept identical to the old flutter_tts based implementation so
/// callers do not need to change.
class TtsService {
  final AudioService _audioService;

  bool _isInitialized = false;

  /// Human-readable diagnostic status from the last initialization attempt.
  String initStatus = '';

  /// Result code from the last speak() call.
  int lastSpeakResult = -999;

  /// The selected engine that was used during initialization.
  String engineName = 'assets';

  /// The list of engines reported by the OS. Always empty in asset mode.
  List<String> availableEngines = [];

  TtsService({AudioService? audioService})
      : _audioService = audioService ?? AudioService();

  bool get isInitialized => _isInitialized;

  /// Initializes the audio playback service.
  ///
  /// Always returns true because the only dependency is bundled assets.
  Future<bool> initialize() async {
    _isInitialized = _audioService.isInitialized;
    initStatus = _isInitialized ? 'assets/ready' : 'assets/unavailable';
    debugPrint('[TTS] audio fallback initialized: $_isInitialized');
    return _isInitialized;
  }

  /// Speaks the given text by mapping it to pre-recorded audio clips.
  ///
  /// Supported inputs:
  /// - Meal-code phrases such as "取餐码是 井 15" or "井 15"
  /// - Fixed prompts: "欢迎使用慧眼...", "没有识别到取餐码..."
  /// - Help prompt: any text containing "帮助" or "操作帮助"
  /// - Distance feedback: "beep_slow" or "beep_fast" (internal codes)
  ///
  /// Dynamic meal codes are decomposed into individual digit clips.
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      debugPrint('[TTS] speak skipped: not initialized');
      return;
    }

    final paths = _mapTextToAssets(text);
    if (paths.isEmpty) {
      debugPrint('[TTS] no audio mapping for: $text');
      lastSpeakResult = 0;
      return;
    }

    final ok = await _audioService.playAssets(paths);
    lastSpeakResult = ok ? 1 : 0;
    debugPrint('[TTS] speak "$text" -> $lastSpeakResult');
  }

  /// Stops current playback.
  Future<void> stop() async {
    await _audioService.stop();
  }

  /// Plays the "识别中，手机请稳一些" scanning prompt.
  Future<void> speakScanning() async {
    if (!_isInitialized) return;
    await _audioService.playAssets(['assets/audio/scanning.mp3']);
  }

  /// Announces multiple meal codes with platforms and positions.
  ///
  /// Format: "识别到2个取餐码。美团外卖 65 号 左上。饿了么 2 号 右上。"
  Future<void> speakMultiCode(List<ScanResult> results) async {
    if (!_isInitialized || results.isEmpty) return;

    final clips = <String>[];

    // "识别到" + count + "个取餐码"
    clips.add('assets/audio/detected.mp3');
    clips.add('assets/audio/num_${results.length}.mp3');
    clips.add('assets/audio/gequcanma.mp3');

    // For each result: platform + digits + "号" + position
    for (final result in results) {
      // Platform audio
      final platAudio = _platformAudio(result.platform);
      if (platAudio != null) clips.add(platAudio);

      // Digits
      final digits = result.code.replaceFirst('#', '');
      for (final d in digits.split('')) {
        clips.add('assets/audio/num_$d.mp3');
      }

      // "号"
      clips.add('assets/audio/hao.mp3');

      // Position audio
      final posAudio = positionAudioAsset(result.positionLabel);
      if (posAudio != null) clips.add(posAudio);
    }

    await _audioService.playAssets(clips);
  }

  /// Formats a meal code for voice announcement.
  ///
  /// The `#` symbol is read as "井" (Chinese for number sign/hash).
  String formatMealCode(String code) {
    final number = code.replaceFirst('#', '');
    return '井 $number';
  }

  /// Formats a meal code with platform name for voice announcement.
  ///
  /// Returns a string like "淘宝闪购 18 号" that [speak] can map
  /// to audio clips. When [platform] is null, omits the platform prefix.
  String formatMealCodeWithPlatform(String code, String? platform) {
    final number = code.replaceFirst('#', '');
    if (platform != null && platform.isNotEmpty) {
      return '$platform $number 号';
    }
    return '$number 号';
  }

  /// Maps a platform display name to its audio asset path.
  ///
  /// Returns null if no audio asset exists for the given platform.
  static String? _platformAudio(String? platform) {
    switch (platform) {
      case '美团外卖':
        return 'assets/audio/meituan.mp3';
      case '饿了么':
        return 'assets/audio/eleme.mp3';
      case '京东外卖':
        return 'assets/audio/jingdong.mp3';
      case '淘宝闪购':
        return 'assets/audio/taobao.mp3';
      default:
        return null;
    }
  }

  /// Maps a text utterance to a sequence of bundled asset paths.
  List<String> _mapTextToAssets(String text) {
    final trimmed = text.trim();

    // Fixed long prompts.
    if (trimmed.contains('欢迎使用慧眼')) {
      return ['assets/audio/tutorial.mp3'];
    }
    if (trimmed.contains('没有识别到取餐码')) {
      return ['assets/audio/none.mp3'];
    }
    if (trimmed.contains('帮助') || trimmed.contains('操作帮助')) {
      return ['assets/audio/help.mp3'];
    }

    // Distance feedback codes (not user-facing text).
    if (trimmed == 'beep_slow') {
      return ['assets/audio/beep_slow.mp3'];
    }
    if (trimmed == 'beep_fast') {
      return ['assets/audio/beep_fast.mp3'];
    }

    // Meal code utterances: "淘宝闪购 18 号" or "18 号".
    final code = _extractCode(trimmed);
    if (code != null && code.isNotEmpty) {
      final clips = <String>[];

      // Detect platform name in the utterance and prepend its audio.
      for (final platform in const [
        '美团外卖',
        '饿了么',
        '京东外卖',
        '淘宝闪购',
      ]) {
        if (trimmed.contains(platform)) {
          final audio = _platformAudio(platform);
          if (audio != null) clips.add(audio);
          break;
        }
      }

      // Digits + "号"
      for (final digit in code.split('')) {
        clips.add('assets/audio/num_$digit.mp3');
      }
      clips.add('assets/audio/hao.mp3');
      return clips;
    }

    return [];
  }

  /// Extracts the digit portion from a meal-code utterance.
  ///
  /// Returns null if no digits are found.
  String? _extractCode(String text) {
    // Remove known Chinese words and the hash symbol, keep digits.
    final digits = text
        .replaceAll(RegExp(r'[^0-9]'), '')
        .trim();
    return digits.isEmpty ? null : digits;
  }
}
