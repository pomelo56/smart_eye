import 'dart:async';

import 'package:flutter/services.dart';

/// Low-level audio player backed by Android MediaPlayer.
///
/// Plays bundled asset files sequentially.  Used as the fallback voice engine
/// on devices where flutter_tts / system TTS cannot be bound.
///
/// [playAssets] blocks until all clips have finished playing, using a native
/// callback ("onPlaybackComplete") instead of estimated delays.
class AudioService {
  static const MethodChannel _channel = MethodChannel('com.smart_eye/audio');

  final bool _isInitialized = true;

  /// Completer for the current playback session. Completed when the native
  /// side signals "onPlaybackComplete" or when [stop] is called.
  Completer<void>? _playbackCompleter;

  bool get isInitialized => _isInitialized;

  AudioService() {
    // Listen for native → Dart callbacks.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPlaybackComplete') {
        _completePlayback();
      }
      return null;
    });
  }

  /// Completes the current playback completer if pending.
  void _completePlayback() {
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }
  }

  /// Plays the given [assetPaths] one after another.
  ///
  /// Blocks until all clips have finished playing (via native callback).
  /// Each path must be relative to the Flutter assets root, e.g.
  /// `'assets/audio/num_1.mp3'`.
  Future<bool> playAssets(List<String> assetPaths, {double volume = 1.0}) async {
    // Complete any pending playback (e.g. from a previous interrupted call).
    _completePlayback();

    _playbackCompleter = Completer<void>();
    try {
      final ok = await _channel.invokeMethod<bool>(
        'playAssets',
        {'paths': assetPaths, 'volume': volume},
      );
      if (ok != true) {
        _completePlayback();
        return false;
      }
      // Wait for native playback to complete.
      await _playbackCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          // Safety timeout: unblock even if native callback is lost.
        },
      );
      return true;
    } catch (e) {
      _completePlayback();
      // ignore: avoid_print
      print('[AudioService] playAssets error: $e');
      return false;
    }
  }

  /// Stops any ongoing playback.
  Future<void> stop() async {
    // Unblock any waiting playAssets call.
    _completePlayback();
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
