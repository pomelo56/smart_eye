import 'dart:async';

import 'package:flutter/services.dart';

/// Low-level audio player backed by Android MediaPlayer.
///
/// Plays bundled asset files sequentially.  Used as the fallback voice engine
/// on devices where flutter_tts / system TTS cannot be bound.
class AudioService {
  static const MethodChannel _channel = MethodChannel('com.smart_eye/audio');

  final bool _isInitialized = true;

  bool get isInitialized => _isInitialized;

  /// Plays the given [assetPaths] one after another.
  ///
  /// Each path must be relative to the Flutter assets root, e.g.
  /// `'assets/audio/num_1.mp3'`.
  Future<bool> playAssets(List<String> assetPaths, {double volume = 1.0}) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'playAssets',
        {'paths': assetPaths, 'volume': volume},
      );
      return ok ?? false;
    } catch (e) {
      // ignore: avoid_print
      print('[AudioService] playAssets error: $e');
      return false;
    }
  }

  /// Stops any ongoing playback.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      // ignore: avoid_print
      print('[AudioService] stop error: $e');
    }
  }

  /// Returns true if the native player reports it is still playing.
  Future<bool> get isPlaying async {
    try {
      final playing = await _channel.invokeMethod<bool>('isPlaying');
      return playing ?? false;
    } catch (e) {
      return false;
    }
  }
}
