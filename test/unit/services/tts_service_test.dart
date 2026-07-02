import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/audio_service.dart';
import 'package:smart_eye/services/tts_service.dart';

class MockAudioService extends Fake implements AudioService {
  final List<String> playedPaths = [];
  bool _initialized = true;

  void setInitialized(bool value) => _initialized = value;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<bool> playAssets(List<String> assetPaths, {double volume = 1.0}) async {
    playedPaths.addAll(assetPaths);
    return true;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  group('TtsService.formatMealCode', () {
    test('formats #15 as 井 15', () {
      final service = TtsService();
      expect(service.formatMealCode('#15'), equals('井 15'));
    });

    test('formats #1 as 井 1', () {
      final service = TtsService();
      expect(service.formatMealCode('#1'), equals('井 1'));
    });

    test('formats #999 as 井 999', () {
      final service = TtsService();
      expect(service.formatMealCode('#999'), equals('井 999'));
    });

    test('handles code without hash prefix', () {
      final service = TtsService();
      expect(service.formatMealCode('15'), equals('井 15'));
    });
  });

  group('TtsService.initialize', () {
    test('returns true when audio service is ready', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      final ok = await service.initialize();
      expect(ok, isTrue);
      expect(service.isInitialized, isTrue);
      expect(service.engineName, equals('assets'));
    });

    test('returns false when audio service is not ready', () async {
      final audio = MockAudioService()..setInitialized(false);
      final service = TtsService(audioService: audio);
      final ok = await service.initialize();
      expect(ok, isFalse);
      expect(service.isInitialized, isFalse);
    });
  });

  group('TtsService.speak', () {
    test('maps meal code to digit clips', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('取餐码是 井 15');

      expect(service.lastSpeakResult, equals(1));
      expect(
        audio.playedPaths,
        equals([
          'assets/audio/prefix.mp3',
          'assets/audio/jing.mp3',
          'assets/audio/num_1.mp3',
          'assets/audio/num_5.mp3',
        ]),
      );
    });

    test('maps tutorial text to tutorial clip', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('欢迎使用慧眼。将手机摄像头对准外卖袋');

      expect(service.lastSpeakResult, equals(1));
      expect(audio.playedPaths, equals(['assets/audio/tutorial.mp3']));
    });

    test('does not throw when not initialized', () async {
      final audio = MockAudioService()..setInitialized(false);
      final service = TtsService(audioService: audio);
      await service.speak('test');
      expect(service.lastSpeakResult, equals(-999));
    });
  });

  group('TtsService.stop', () {
    test('stops without error', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.stop();
    });
  });
}
