import 'package:connectivity_plus/connectivity_plus.dart';

/// Wrapper around `connectivity_plus` that exposes only the Wi-Fi check
/// needed by the update feature.
///
/// The abstraction makes it possible to inject a fake in unit tests without
/// touching the plugin's MethodChannel.
class ConnectivityService {
  final Future<List<ConnectivityResult>> Function() _check;

  /// Creates a [ConnectivityService].
  ///
  /// The optional [check] parameter is used in tests to override the real
  /// plugin call.
  ConnectivityService({Future<List<ConnectivityResult>> Function()? check})
      : _check = check ?? (() => Connectivity().checkConnectivity());

  /// Returns true if the device is currently connected to a Wi-Fi network.
  ///
  /// Mobile data, VPN-only, or disconnected states all return false so the
  /// update check does not consume cellular bandwidth.
  Future<bool> get isWifiConnected async {
    final results = await _check();
    return results.contains(ConnectivityResult.wifi);
  }
}
