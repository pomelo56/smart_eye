import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_eye/services/file_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return <String, String>{'path': '/tmp'};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FileLogger.screenBufferNotifier', () {
    test('notifier updates when a log line is written', () async {
      final logger = FileLogger.instance;
      await logger.initialize();

      var notified = false;
      void listener() => notified = true;
      logger.screenBufferNotifier.addListener(listener);

      await logger.write('INFO', 'notifier test');

      expect(notified, isTrue);
      expect(logger.screenBuffer.last, contains('notifier test'));

      logger.screenBufferNotifier.removeListener(listener);
    });

    test('notifier keeps at most maxScreenLines entries', () async {
      final logger = FileLogger.instance;
      await logger.initialize();

      final values = <List<String>>[];
      void listener() => values.add(List.of(logger.screenBuffer));
      logger.screenBufferNotifier.addListener(listener);

      for (var i = 0; i < FileLogger.maxScreenLines + 2; i++) {
        await logger.write('INFO', 'line $i');
      }

      expect(logger.screenBuffer.length, equals(FileLogger.maxScreenLines));
      expect(values.last.length, equals(FileLogger.maxScreenLines));

      logger.screenBufferNotifier.removeListener(listener);
    });
  });
}
