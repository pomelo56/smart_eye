import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Asserts that R8 code shrinking is correctly configured for the
/// release build type.
///
/// This test exists because R8 stripping is silent: if the build
/// configuration regresses, the APK will be larger than expected
/// and the size budget in docs/APK_SIZE_OPTIMIZATION.md will not
/// be met. Catching the regression in `flutter test` is much
/// faster than discovering it after a 5-minute build.
///
/// What we check:
/// 1. `android/app/build.gradle` enables `minifyEnabled true` on release
/// 2. `android/app/build.gradle` enables `shrinkResources true` on release
/// 3. `proguardFiles` references `proguard-rules.pro`
/// 4. `proguard-rules.pro` has keep rules for ML Kit (would otherwise crash)
/// 5. `proguard-rules.pro` has keep rules for MainActivity entry point
void main() {
  group('R8 / build config', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();
    final proguardRules =
        File('android/app/proguard-rules.pro').readAsStringSync();

    test('release build enables minifyEnabled true (R8 code shrinking)', () {
      // The release block should contain `minifyEnabled true` (Groovy DSL).
      // We don't try to parse Gradle — we just assert the substring exists.
      expect(
        buildGradle,
        contains('minifyEnabled true'),
        reason: 'R8 code shrinking is required to hit the <25 MB release '
            'APK target. See docs/APK_SIZE_OPTIMIZATION.md.',
      );
    });

    test('release build enables shrinkResources true (resource shrinking)', () {
      expect(
        buildGradle,
        contains('shrinkResources true'),
        reason: 'Resource shrinking removes unused drawables/strings and '
            'saves another 0.5-1 MB on top of R8.',
      );
    });

    test('proguardFiles references proguard-rules.pro (keep rules loaded)', () {
      expect(
        buildGradle,
        contains('proguard-rules.pro'),
        reason: 'Without this reference, R8 will use the default rules '
            'only and strip ML Kit classes, crashing at startup.',
      );
    });

    test('proguard-rules.pro keeps ML Kit text recognition classes', () {
      // ML Kit uses reflection; without this rule the app crashes on
      // first OCR call.
      expect(
        proguardRules,
        contains('com.google.mlkit.vision.text'),
        reason: 'ML Kit text recognizer classes are loaded via reflection. '
            'R8 must not strip them.',
      );
    });

    test('proguard-rules.pro keeps MainActivity (MethodChannel entry point)',
        () {
      // MainActivity is the entry point for the audio MethodChannel.
      // If R8 strips it, the app launches but audio is silent.
      expect(
        proguardRules,
        contains('com.example.smart_eye.MainActivity'),
        reason: 'MainActivity is referenced from AndroidManifest.xml but '
            'R8 sometimes cannot follow the manifest reference early '
            'enough, so we keep it explicitly.',
      );
    });

    test('androidx.core is declared for the camera permission flow', () {
      // v0.7.1 uses ContextCompat.checkSelfPermission and
      // ActivityCompat.requestPermissions in MainActivity.kt. Without
      // this dependency, the Kotlin code fails to compile.
      expect(
        buildGradle,
        contains('androidx.core:core-ktx'),
        reason: 'MainActivity uses ContextCompat / ActivityCompat. The '
            'core-ktx dependency must be declared explicitly so the '
            'permission channel compiles.',
      );
    });

    test('MainActivity registers the permission MethodChannel handler', () {
      // The handler in MainActivity.kt maps to the Dart side's
      // com.smart_eye/permission channel. If someone removes it, the
      // PermissionService silently reports "unknown" and the user sees
      // no feedback when the camera is denied.
      final mainActivity = File(
        'android/app/src/main/kotlin/com/example/smart_eye/MainActivity.kt',
      ).readAsStringSync();
      expect(
        mainActivity,
        contains('com.smart_eye/permission'),
        reason: 'The v0.7.1 camera permission flow requires the '
            'permission MethodChannel in MainActivity. Removing this '
            'string silences the permission prompts entirely.',
      );
      expect(
        mainActivity,
        contains('openAppSettings'),
        reason: 'The user must be able to navigate to the system '
            'settings page to manually grant a permanently denied '
            'permission.',
      );
    });
  });
}
