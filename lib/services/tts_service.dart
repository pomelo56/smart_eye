import 'dart:async';

import 'package:flutter/foundation.dart';

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

  /// Formats a meal code for voice announcement.
  ///
  /// The `#` symbol is read as "井" (Chinese for number sign/hash).
  String formatMealCode(String code) {
    final number = code.replaceFirst('#', '');
    return '井 $number';
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

    // Meal code utterances: "取餐码是 井 15" or "井 15".
    final code = _extractCode(trimmed);
    if (code != null && code.isNotEmpty) {
      final clips = <String>['assets/audio/prefix.mp3', 'assets/audio/jing.mp3'];
      for (final digit in code.split('')) {
        final path = 'assets/audio/num_$digit.mp3';
        clips.add(path);
      }
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
