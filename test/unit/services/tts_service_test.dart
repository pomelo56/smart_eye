import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/audio_service.dart';
import 'package:smart_eye/services/tts_service.dart';

class MockAudioService extends Fake implements AudioService {
  final List<String> playedPaths = [];
  bool _initialized = true;

  void setInitialized(bool value) => _initialized = value;

  @override
  Future<bool> initialize() async => _initialized;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<bool> playAssets(List<String> assetPaths,
      {double volume = 1.0}) async {
    playedPaths.addAll(assetPaths);
    return true;
  }

  @override
  Future<bool> stop() async => _initialized;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsService.formatMealCode', () {
    test('formats #15 as 井 15', () {
      final service = TtsService(audioService: MockAudioService());
      expect(service.formatMealCode('#15'), equals('井 15'));
    });

    test('formats #1 as 井 1', () {
      final service = TtsService(audioService: MockAudioService());
      expect(service.formatMealCode('#1'), equals('井 1'));
    });

    test('formats #999 as 井 999', () {
      final service = TtsService(audioService: MockAudioService());
      expect(service.formatMealCode('#999'), equals('井 999'));
    });

    test('handles code without hash prefix', () {
      final service = TtsService(audioService: MockAudioService());
      expect(service.formatMealCode('15'), equals('井 15'));
    });
  });

  group('TtsService.formatMealCodeWithPlatform', () {
    test('formats with platform name', () {
      final service = TtsService();
      expect(
        service.formatMealCodeWithPlatform('#18', '淘宝闪购'),
        equals('淘宝闪购 18 号'),
      );
    });

    test('formats without platform when null', () {
      final service = TtsService();
      expect(
        service.formatMealCodeWithPlatform('#18', null),
        equals('18 号'),
      );
    });

    test('formats without platform when empty', () {
      final service = TtsService();
      expect(
        service.formatMealCodeWithPlatform('#18', ''),
        equals('18 号'),
      );
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
      await service.speak('15 号');

      expect(service.lastSpeakResult, equals(1));
      expect(
        audio.playedPaths,
        equals([
          'assets/audio/num_1.mp3',
          'assets/audio/num_5.mp3',
          'assets/audio/hao.mp3',
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

    test('maps help text to help clip', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('操作帮助');

      expect(service.lastSpeakResult, equals(1));
      expect(audio.playedPaths, equals(['assets/audio/help.mp3']));
    });

    test('maps beep codes to feedback clips', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('beep_slow');
      await service.speak('beep_fast');

      expect(
          audio.playedPaths,
          equals([
            'assets/audio/beep_slow.mp3',
            'assets/audio/beep_fast.mp3',
          ]));
    });

    test('does not throw when not initialized', () async {
      final audio = MockAudioService()..setInitialized(false);
      final service = TtsService(audioService: audio);
      await service.speak('test');
      expect(service.lastSpeakResult, equals(-999));
    });

    test('maps "没有识别到取餐码" text to none clip', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('没有识别到取餐码');

      expect(service.lastSpeakResult, equals(1));
      expect(audio.playedPaths, equals(['assets/audio/none.mp3']));
    });

    test('speakDetectedTakeout plays the 3-clip sequence', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speakDetectedTakeout();

      expect(service.lastSpeakResult, equals(1));
      expect(
          audio.playedPaths,
          equals([
            'assets/audio/faxian_waimai.mp3',
            'assets/audio/shibiezhong.mp3',
            'assets/audio/please_steady.mp3',
          ]));
    });

    test('speakDetectedTakeout is no-op when not initialized', () async {
      final audio = MockAudioService()..setInitialized(false);
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speakDetectedTakeout();
      expect(audio.playedPaths, isEmpty);
    });

    test('maps digit text with 号 suffix to digit clips', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('123 号');

      expect(service.lastSpeakResult, equals(1));
      expect(
          audio.playedPaths,
          equals([
            'assets/audio/num_1.mp3',
            'assets/audio/num_2.mp3',
            'assets/audio/num_3.mp3',
            'assets/audio/hao.mp3',
          ]));
    });

    test('maps platform name + meal code to platform clips', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('淘宝闪购 18 号');

      expect(service.lastSpeakResult, equals(1));
      expect(
          audio.playedPaths,
          equals([
            'assets/audio/taobao.mp3',
            'assets/audio/num_1.mp3',
            'assets/audio/num_8.mp3',
            'assets/audio/hao.mp3',
          ]));
    });

    test('maps Meituan platform name to meituan clip', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('美团外卖 65 号');

      expect(
          audio.playedPaths,
          equals([
            'assets/audio/meituan.mp3',
            'assets/audio/num_6.mp3',
            'assets/audio/num_5.mp3',
            'assets/audio/hao.mp3',
          ]));
    });

    test('maps unknown platform without platform clip', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('15 号');

      expect(
          audio.playedPaths,
          equals([
            'assets/audio/num_1.mp3',
            'assets/audio/num_5.mp3',
            'assets/audio/hao.mp3',
          ]));
    });

    test('returns empty paths for unmapped text', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      await service.speak('随机无关文本');

      expect(service.lastSpeakResult, equals(0));
      expect(audio.playedPaths, isEmpty);
    });
  });

  group('TtsService.stop', () {
    test('returns true when initialized and native stop succeeds', () async {
      final audio = MockAudioService();
      final service = TtsService(audioService: audio);
      await service.initialize();
      final ok = await service.stop();
      expect(ok, isTrue);
    });

    test('returns false when not initialized', () async {
      final audio = MockAudioService()..setInitialized(false);
      final service = TtsService(audioService: audio);
      await service.initialize();
      final ok = await service.stop();
      expect(ok, isFalse);
    });
  });
}
