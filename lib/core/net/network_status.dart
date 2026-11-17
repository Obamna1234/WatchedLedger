import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Knows whether the phone is on Wi-Fi or mobile data (no network requests
/// are made to find out; the phone's own connection state is read).
class NetworkStatus extends ChangeNotifier {
  NetworkStatus({Connectivity? connectivity}) : _connectivity = connectivity;

  final Connectivity? _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _current = const [];

  Future<void> start() async {
    final c = _connectivity ?? Connectivity();
    try {
      _current = await c.checkConnectivity();
      _sub = c.onConnectivityChanged.listen(update);
    } catch (_) {
      // Unknown connection type: requests are allowed and simply fail
      // if there is no network.
    }
  }

  @visibleForTesting
  void update(List<ConnectivityResult> results) {
    _current = List.unmodifiable(results);
    notifyListeners();
  }

  /// On mobile data and not on Wi-Fi / ethernet at the same time.
  bool get isMetered =>
      _current.contains(ConnectivityResult.mobile) &&
      !_current.contains(ConnectivityResult.wifi) &&
      !_current.contains(ConnectivityResult.ethernet);

  bool get isOnWifi =>
      _current.contains(ConnectivityResult.wifi) ||
      _current.contains(ConnectivityResult.ethernet);

  bool get hasNoConnection =>
      _current.isNotEmpty &&
      _current.every((r) => r == ConnectivityResult.none);

  String get label {
    if (isOnWifi) return 'On Wi-Fi';
    if (isMetered) return 'On mobile data';
    if (hasNoConnection) return 'No connection';
    return 'Connection type unknown';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
