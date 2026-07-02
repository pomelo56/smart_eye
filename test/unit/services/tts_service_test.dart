import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/tts_service.dart';

class MockFlutterTts extends Fake implements FlutterTts {
  String? lastLanguage;
  double lastSpeechRate = 0;
  double lastVolume = 0;
  double lastPitch = 0;
  bool awaitSpeakCompletionValue = false;

  @override
  Future<dynamic> setLanguage(String language) async {
    lastLanguage = language;
    return 1; // success
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    lastSpeechRate = rate;
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    lastVolume = volume;
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    lastPitch = pitch;
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    awaitSpeakCompletionValue = awaitCompletion;
    return 1;
  }

  @override
  Future<dynamic> speak(String text) async {
    return 1; // success
  }

  @override
  Future<dynamic> stop() async {
    return 1;
  }
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
    test('sets initialized to true on success', () async {
      final mockTts = MockFlutterTts();
      final service = TtsService(flutterTts: mockTts);
      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(mockTts.awaitSpeakCompletionValue, isFalse);
      expect(mockTts.lastLanguage, equals('zh-CN'));
      expect(mockTts.lastSpeechRate, equals(1.0));
      expect(mockTts.lastVolume, equals(1.0));
      expect(mockTts.lastPitch, equals(1.0));
    });

    test('tries alternative locales when zh-CN fails', () async {
      final mockTts = MockFlutterTts();
      mockTts.setLanguage = (String language) async {
        mockTts.lastLanguage = language;
        if (language == 'zh-CN') return 0; // fail
        if (language == 'zh-TW') return 1; // success
        return 0;
      };
      final service = TtsService(flutterTts: mockTts);
      await service.initialize();
      expect(service.isInitialized, isTrue);
    });
  });

  group('TtsService.speak', () {
    test('speaks when initialized', () async {
      final mockTts = MockFlutterTts();
      final service = TtsService(flutterTts: mockTts);
      await service.initialize();
      await service.speak('取餐码是 井 15');
      expect(service.lastSpeakResult, equals(1));
    });

    test('does not throw when not initialized', () async {
      final service = TtsService();
      // Should not throw, just skip
      await service.speak('test');
    });
  });

  group('TtsService.stop', () {
    test('stops without error', () async {
      final mockTts = MockFlutterTts();
      final service = TtsService(flutterTts: mockTts);
      await service.initialize();
      await service.stop();
    });
  });
}
