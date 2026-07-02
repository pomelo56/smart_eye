import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service for text-to-speech voice feedback.
///
/// Uses flutter_tts plugin with OPPO/ColorOS compatibility settings.
class TtsService {
  final FlutterTts _flutterTts;
  bool _isInitialized = false;

  TtsService({FlutterTts? flutterTts}) : _flutterTts = flutterTts ?? FlutterTts();

  bool get isInitialized => _isInitialized;

  /// Diagnostic info
  String initStatus = '';
  int lastSpeakResult = -999;

  /// Initializes TTS with OPPO-compatible settings.
  Future<void> initialize() async {
    try {
      // CRITICAL: Disable awaitSpeakCompletion to prevent hang on OPPO
      await _flutterTts.awaitSpeakCompletion(false);
      debugPrint('[TTS] awaitSpeakCompletion=false');

      // Set language
      var langResult = await _flutterTts.setLanguage('zh-CN');
      debugPrint('[TTS] setLanguage zh-CN: $langResult');
      initStatus = 'zh-CN=$langResult';

      if (langResult != 1) {
        // Try alternative locales
        for (final lang in ['zh-TW', 'zh', 'cmn-CN']) {
          langResult = await _flutterTts.setLanguage(lang);
          debugPrint('[TTS] setLanguage $lang: $langResult');
          if (langResult == 1) {
            initStatus = '$lang=$langResult';
            break;
          }
        }
      }

      await _flutterTts.setSpeechRate(1.0);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInitialized = true;
      debugPrint('[TTS] init OK');
    } catch (e) {
      debugPrint('[TTS] init error: $e');
      initStatus = 'error: $e';
      _isInitialized = false;
    }
  }

  /// Speaks the given text.
  /// Fire-and-forget (does not wait for completion).
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      debugPrint('[TTS] speak skipped: not initialized');
      return;
    }
    try {
      lastSpeakResult = await _flutterTts.speak(text);
      debugPrint('[TTS] speak "$text" -> $lastSpeakResult');
    } catch (e) {
      debugPrint('[TTS] speak error: $e');
      lastSpeakResult = -999;
    }
  }

  /// Stops current speech.
  Future<void> stop() async {
    if (!_isInitialized) return;
    await _flutterTts.stop();
  }

  /// Formats a meal code for TTS announcement.
  String formatMealCode(String code) {
    final number = code.replaceFirst('#', '');
    return '井 $number';
  }
}
