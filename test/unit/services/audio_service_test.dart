import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.smart_eye/audio');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'ping':
          return true;
        case 'playAssets':
          return true;
        case 'stop':
          return true;
        case 'isPlaying':
          return false;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AudioService.initialize', () {
    test('returns true when native channel responds', () async {
      final service = AudioService();
      final ok = await service.initialize();

      expect(ok, isTrue);
      expect(service.isInitialized, isTrue);
      expect(log.any((c) => c.method == 'ping'), isTrue);
    });

    test('returns false when native channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR');
      });

      final service = AudioService();
      final ok = await service.initialize();

      expect(ok, isFalse);
      expect(service.isInitialized, isFalse);
    });
  });

  group('AudioService.stop', () {
    test('returns true on success', () async {
      final service = AudioService();
      await service.initialize();
      final ok = await service.stop();

      expect(ok, isTrue);
      expect(log.any((c) => c.method == 'stop'), isTrue);
    });

    test('returns false when native channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'stop') {
          throw PlatformException(code: 'ERROR');
        }
        return true;
      });

      final service = AudioService();
      await service.initialize();
      final ok = await service.stop();

      expect(ok, isFalse);
    });
  });
}
