# ============================================================
# R8 / ProGuard rules for smart_eye
# ============================================================
# Last updated: v0.7.0 (R8 code shrinking enabled)
# Test that asserts these rules are present:
#   test/unit/build/build_config_test.dart
#
# When adding a new third-party library that uses reflection,
# JNI, or annotation processing, add a -keep rule here. Otherwise
# R8 will strip the classes and the app will crash at runtime.
# ============================================================

# --- ML Kit Text Recognition ---
# Keep all ML Kit text recognizer classes (Chinese, Latin, etc.)
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.latin.**

# Flutter plugin wrapper for ML Kit
-keep class io.flutter.plugins.google.mlkit.textrecognition.** { *; }

# --- Flutter framework ---
# Flutter engine uses reflection on @Keep-annotated classes.
# The default proguard-android-optimize.txt already covers most of this,
# but we add explicit rules to be safe.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- MethodChannel entry points ---
# MainActivity.kt is referenced by AndroidManifest.xml, but R8 sometimes
# strips it if the manifest is not parsed early. Keep it explicitly.
-keep class com.smart_eye.MainActivity { *; }

# --- Kotlin metadata ---
# Required for Kotlin reflection used by some plugins.
-keep class kotlin.Metadata { *; }
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
-keepattributes Signature,InnerClasses,EnclosingMethod
-keepattributes AnnotationDefault

# --- Camera plugin ---
# The `camera` Flutter plugin uses platform channels and reflection
# on CameraDevice / Camera2 classes. R8 sometimes can't follow the
# reflection chain, so we keep the public Android Camera API.
-keep class android.hardware.camera2.** { *; }
-dontwarn android.hardware.camera2.**

# --- Google Play dynamic feature delivery ---
# smart_eye is distributed as a direct APK (not via Google Play),
# so the Play Core split-install classes are never present at runtime.
# Flutter's FlutterPlayStoreSplitApplication references them via the
# `app` split manifest. Suppress the R8 missing-class warning.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
