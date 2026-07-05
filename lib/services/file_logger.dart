import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent file logger for field diagnostics.
///
/// Writes all log messages to a timestamped file in the app's
/// documents directory. Logs are rotated daily (max 7 days).
/// Use [export] to copy the current log to a user-accessible path.
class FileLogger {
  static FileLogger? _instance;
  static FileLogger get instance => _instance ??= FileLogger._();
  FileLogger._();

  File? _logFile;
  String? _logDir;
  bool _initialized = false;

  /// Maximum log files to keep (7 days).
  static const _maxLogFiles = 7;

  /// In-memory buffer for screen display.
  final List<String> screenBuffer = [];

  /// Maximum number of lines shown on the screen overlay.
  static const maxScreenLines = 8;

  /// Notifies listeners when [screenBuffer] changes.
  ///
  /// Widgets can listen to this instead of rebuilding on every log write
  /// via a full setState.
  final ValueNotifier<List<String>> screenBufferNotifier =
      ValueNotifier<List<String>>(const []);

  /// Initialize the logger. Call once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logDir = dir.path;
      await _rotateIfNeeded();
      _logFile = await _createLogFile();
      _initialized = true;
      await write('INFO', 'FileLogger 初始化完成, dir=$_logDir');
    } catch (e) {
      debugPrint('[FileLogger] 初始化失败: $e');
    }
  }

  Future<File> _createLogFile() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final filename = 'smarteye_${dateStr}_$timeStr.log';
    return File('$_logDir/$filename');
  }

  Future<void> _rotateIfNeeded() async {
    if (_logDir == null) return;
    final dir = Directory(_logDir!);
    if (!await dir.exists()) return;

    final logFiles = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .cast<File>()
        .toList();

    if (logFiles.length <= _maxLogFiles) return;

    // Sort by modification time, delete oldest
    logFiles.sort((a, b) {
      return FileStat.statSync(a.path)
          .modified
          .compareTo(FileStat.statSync(b.path).modified);
    });

    final toDelete = logFiles.length - _maxLogFiles;
    for (var i = 0; i < toDelete; i++) {
      try {
        await logFiles[i].delete();
      } catch (_) {}
    }
  }

  /// Write a log line to both file and screen buffer.
  Future<void> write(String level, String message) async {
    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final line = '[$timestamp][$level] $message';

    // Screen buffer (for overlay display)
    if (screenBuffer.length >= maxScreenLines) {
      screenBuffer.removeAt(0);
    }
    screenBuffer.add(line);
    screenBufferNotifier.value = List<String>.unmodifiable(screenBuffer);

    // debugPrint for logcat
    debugPrint('[慧眼] $line');

    // File write (fire-and-forget to avoid blocking)
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString('$line\n', mode: FileMode.append);
      } catch (e) {
        debugPrint('[FileLogger] 写入失败: $e');
      }
    }
  }

  /// Export current log file content as a string.
  Future<String> exportContent() async {
    if (_logFile == null || !await _logFile!.exists()) {
      return 'No log file available';
    }
    try {
      return await _logFile!.readAsString();
    } catch (e) {
      return 'Error reading log: $e';
    }
  }

  /// Copy current log to Downloads directory for easy sharing.
  /// Returns the export path, or null on failure.
  Future<String?> exportToDownloads() async {
    if (_logFile == null || !await _logFile!.exists()) return null;

    try {
      // Try /storage/emulated/0/Download (most Android devices)
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        // Fallback: use app's external storage
        final extDir = await getExternalStorageDirectory();
        if (extDir == null) return null;
        final target = File('${extDir.path}/${_logFile!.path.split('/').last}');
        await _logFile!.copy(target.path);
        return target.path;
      }

      final filename = _logFile!.path.split('/').last;
      final target = File('${downloadsDir.path}/$filename');
      await _logFile!.copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('[FileLogger] 导出失败: $e');
      return null;
    }
  }

  /// Get the current log file path.
  String? get logFilePath => _logFile?.path;

  /// Get all log file paths.
  Future<List<String>> getLogFiles() async {
    if (_logDir == null) return [];
    final dir = Directory(_logDir!);
    if (!await dir.exists()) return [];
    return dir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .map((e) => e.path)
        .toList();
  }
}
