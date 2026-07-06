import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Asserts that every .mp3 file under `assets/audio/` is referenced
/// somewhere in `lib/`.
///
/// This prevents shipping unused audio assets (which would inflate
/// the APK) and also prevents deleting an audio file that is still
/// referenced by the code (which would crash at runtime).
void main() {
  group('Audio assets inventory', () {
    final audioDir = Directory('assets/audio');
    final libDir = Directory('lib');

    test('every assets/audio/*.mp3 is referenced in lib/', () {
      final files = audioDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();

      // Concatenate every Dart source file in lib/.
      final libSource = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      // For each audio file, derive a "key" — the part that is most likely
      // to appear in code as a literal or interpolated path. Examples:
      //   closer.mp3          → "closer"
      //   num_5.mp3           → "num_5" (literal)  OR  "num_" (interpolated)
      //   pos_bottomleft.mp3  → "pos_bottomleft"
      //
      // Matching rules (any of):
      //   1. The exact base name appears as a literal in lib/.
      //   2. The prefix up to the last "_" appears with a "." after it
      //      (catches interpolated patterns like "num_$digit.mp3").
      //   3. The base contains a digit suffix (e.g. "num_0") and the lib
      //      source contains "num_" anywhere — this protects the entire
      //      num_0..9 family whenever any one of them is referenced.
      final orphans = <String>[];
      final hasNumPrefix = libSource.contains('num_');
      for (final filename in files) {
        final base = filename.replaceAll('.mp3', '');
        final prefix = base.contains('_')
            ? base.substring(0, base.lastIndexOf('_'))
            : base;
        final isNumFamily = base.startsWith('num_');
        final ok = libSource.contains(base) ||
            libSource.contains('$prefix.') ||
            (isNumFamily && hasNumPrefix);
        if (!ok) {
          orphans.add(filename);
        }
      }

      expect(
        orphans,
        isEmpty,
        reason: 'Orphan audio files (not referenced in lib/): $orphans\n'
            'Either remove them (run `git rm assets/audio/<name>.mp3`) or '
            'add the reference in the appropriate TtsService / HomeScreen / '
            'ScanResult file.',
      );
    });
  });
}
