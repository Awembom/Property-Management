import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Is the app online? Two signals together:
/// - [hasNetwork]: the phone has Wi-Fi or mobile data (from the system);
/// - [serverReachable]: the last request to Supabase got an answer (Wi-Fi
///   without internet or a very weak signal only shows up here).
class ConnectionInfo {
  const ConnectionInfo({
    required this.hasNetwork,
    required this.serverReachable,
    this.lastFailureAt,
  });

  final bool hasNetwork;
  final bool serverReachable;

  /// When a request last failed for lack of connection.
  final DateTime? lastFailureAt;

  bool get online => hasNetwork && serverReachable;

  /// Recently failed: skip the slow network attempt and use saved data first.
  bool get recentlyFailed =>
      !serverReachable &&
      lastFailureAt != null &&
      DateTime.now().difference(lastFailureAt!) < const Duration(seconds: 20);
}

class ConnectionNotifier extends Notifier<ConnectionInfo> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  ConnectionInfo build() {
    try {
      final connectivity = Connectivity();
      _subscription = connectivity.onConnectivityChanged.listen(_onChanged, onError: (_) {});
      connectivity.checkConnectivity().then(_onChanged, onError: (_) {});
    } catch (_) {
      // No connectivity plugin (tests): assume online.
    }
    ref.onDispose(() => _subscription?.cancel());
    return const ConnectionInfo(hasNetwork: true, serverReachable: true);
  }

  void _onChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (hasNetwork == state.hasNetwork) return;
    // Network came back: assume the server is reachable until a request says not.
    state = ConnectionInfo(hasNetwork: hasNetwork, serverReachable: hasNetwork || state.serverReachable);
  }

  /// Called after every request: did it reach the server?
  void reportRequest({required bool reached}) {
    if (reached) {
      if (!state.serverReachable) {
        state = ConnectionInfo(hasNetwork: true, serverReachable: true);
      }
    } else {
      state = ConnectionInfo(
        hasNetwork: state.hasNetwork,
        serverReachable: false,
        lastFailureAt: DateTime.now(),
      );
    }
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionInfo>(ConnectionNotifier.new);
