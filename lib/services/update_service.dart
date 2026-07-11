import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connectivity_service.dart';

/// Information about a remote app update.
class UpdateInfo {
  /// Creates an [UpdateInfo].
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  /// Remote Android `versionCode` (e.g. 14).
  final int versionCode;

  /// Human-readable version name parsed from the release tag (e.g. "0.8.0").
  final String versionName;

  /// Direct download URL for `app-release.apk`.
  final String downloadUrl;

  /// Release notes or body text from the release page.
  final String releaseNotes;
}

/// Checks Gitee/GitHub Releases for a newer APK.
///
/// Update source priority (documented in MEMORY.md):
/// 1. Gitee Releases — primary source for mainland China users (faster).
/// 2. GitHub Releases — fallback when Gitee is unavailable or not synced.
///
/// The check is throttled to once per week and only runs on Wi-Fi to avoid
/// surprising users with cellular data usage.
///
/// **CVE-STYLE-004:** Download URLs are validated against a trusted domain
/// whitelist to prevent redirection to malicious servers even if the API
/// response is tampered with.
class UpdateService {
  static const _lastCheckKey = 'last_update_check_millis';
  static const _checkInterval = Duration(days: 7);
  static const _assetName = 'app-release.apk';

  static const _giteeLatestUrl =
      'https://gitee.com/api/v5/repos/free-style_2_0/smart_eye/releases/latest';
  static const _githubLatestUrl =
      'https://api.github.com/repos/pomelo56/smart_eye/releases/latest';

  /// CVE-STYLE-004: Trusted domains for APK downloads.
  ///
  /// Even if the release API response is tampered with, download URLs must
  /// point to one of these domains. This prevents redirection to attacker-
  /// controlled servers.
  static const _trustedDownloadDomains = <String>{
    'gitee.com',
    'dl.gitee.com',
    'github.com',
    'objects.githubusercontent.com',
    'github-releases.githubusercontent.com',
  };

  final SharedPreferences _prefs;
  final ConnectivityService _connectivity;
  final Dio _dio;
  final PackageInfo _packageInfo;
  final DateTime Function() _clock;

  /// Validates that [url] is an HTTPS URL pointing to a trusted domain.
  ///
  /// Returns false for:
  /// - Empty or malformed URLs
  /// - Non-HTTPS schemes (http://, file://, content://, etc.)
  /// - Domains not in [_trustedDownloadDomains]
  static bool isValidDownloadUrl(String url) {
    if (url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;

    final host = uri.host;
    return _trustedDownloadDomains.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    );
  }

  /// Creates an [UpdateService].
  UpdateService({
    required SharedPreferences prefs,
    required ConnectivityService connectivity,
    required Dio dio,
    required PackageInfo packageInfo,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _connectivity = connectivity,
        _dio = dio,
        _packageInfo = packageInfo,
        _clock = clock ?? DateTime.now;

  /// Returns [UpdateInfo] when a newer version is available, or `null` when
  /// there is no update, the device is not on Wi-Fi, or the check was already
  /// performed within the last 7 days.
  ///
  /// Throws on network or parsing errors; callers should catch and provide
  /// voice feedback.
  Future<UpdateInfo?> checkForUpdate() async {
    if (!await _connectivity.isWifiConnected) return null;

    final lastCheckMillis = _prefs.getInt(_lastCheckKey);
    final now = _clock();
    if (lastCheckMillis != null) {
      final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckMillis);
      if (now.difference(lastCheck) < _checkInterval) return null;
    }

    try {
      final info = await _fetchLatest(_giteeLatestUrl);
      await _markChecked(now);
      return info;
    } catch (_) {
      // Gitee failed — try GitHub before giving up.
      final info = await _fetchLatest(_githubLatestUrl);
      await _markChecked(now);
      return info;
    }
  }

  /// Parses a release response and returns an [UpdateInfo] only when the
  /// remote version is newer than the local version.
  Future<UpdateInfo?> _fetchLatest(String url) async {
    final response = await _dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        validateStatus: (status) => status == 200,
        responseType: ResponseType.json,
      ),
    );

    final data = response.data;
    if (data == null) throw Exception('empty release response');

    final tag = data['tag_name'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final remoteVersionCode = _extractVersionCode(tag, body);
    if (remoteVersionCode == null) {
      throw Exception('cannot parse versionCode from tag "$tag"');
    }

    final assets =
        (data['assets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final asset = assets.firstWhere(
      (a) => a['name'] == _assetName,
      orElse: () => <String, dynamic>{},
    );
    final downloadUrl = asset['browser_download_url'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('$_assetName not found in release assets');
    }
    // CVE-STYLE-004: Validate download URL against trusted domain whitelist
    if (!isValidDownloadUrl(downloadUrl)) {
      throw Exception(
          'Download URL is not from a trusted domain: $downloadUrl');
    }

    final localVersionCode = int.tryParse(_packageInfo.buildNumber) ?? 0;
    if (remoteVersionCode <= localVersionCode) return null;

    return UpdateInfo(
      versionCode: remoteVersionCode,
      versionName: tag
          .replaceFirst(RegExp(r'^v'), '')
          .replaceFirst(RegExp(r'\+\d+\s*$'), ''),
      downloadUrl: downloadUrl,
      releaseNotes: body,
    );
  }

  /// Extracts the Android version code from the release tag or body.
  ///
  /// Preferred format: tag ending with `+NNN` (e.g. `v0.8.0+14`).
  /// Fallback: `versionCode: NNN` anywhere in the release body.
  int? _extractVersionCode(String tag, String body) {
    final tagMatch = RegExp(r'\+(\d+)\s*$').firstMatch(tag);
    if (tagMatch != null) return int.tryParse(tagMatch.group(1)!);

    final bodyMatch = RegExp(r'[Vv]ersionCode[:\s]*(\d+)').firstMatch(body);
    if (bodyMatch != null) return int.tryParse(bodyMatch.group(1)!);

    return null;
  }

  Future<void> _markChecked(DateTime now) async {
    await _prefs.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
  }
}
