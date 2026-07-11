import 'dart:io';

import 'package:flutter/services.dart';

/// APK签名校验服务，防止恶意APK安装（CVE-STYLE-001）
///
/// 这是防御供应链攻击的核心防护：即使MITM替换了下载的APK，
/// 由于签名与当前应用不一致，安装会被阻止。
///
/// 说明：Android系统本身在安装时也会校验签名（更新时签名必须一致），
/// 此处提前校验是为了：
/// 1. 在调用系统安装器之前就拦截恶意APK
/// 2. 给用户明确的语音警告（遵循NSF红线）
class ApkVerifier {
  static const _channel = MethodChannel('com.smart_eye/apk_verifier');

  /// 校验APK文件签名是否与当前应用一致
  ///
  /// 返回true表示APK签名可信，可以安全安装；
  /// 返回false表示签名不匹配、文件损坏或不存在。
  Future<bool> isApkTrusted(String apkPath) async {
    if (apkPath.isEmpty) return false;
    try {
      final file = File(apkPath);
      if (!await file.exists()) return false;

      final result = await _channel.invokeMethod<bool>(
        'verifyApkSignature',
        {'path': apkPath},
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
