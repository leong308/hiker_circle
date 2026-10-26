// NetworkReachabilityService combines connection-change events with reachability probes and shares
// one current online/offline snapshot.
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Defines the network reachability state choices.
enum NetworkReachabilityState { checking, online, offline }

/// Represents network reachability snapshot.
class NetworkReachabilitySnapshot {
  /// Creates network reachability snapshot.
  const NetworkReachabilitySnapshot({required this.state, this.message});

  final NetworkReachabilityState state;
  final String? message;

  /// Returns is online.
  bool get isOnline => state == NetworkReachabilityState.online;
}

/// Represents network reachability service.
class NetworkReachabilityService {
  /// Creates network reachability service using .
  NetworkReachabilityService._();

  static final NetworkReachabilityService instance =
      NetworkReachabilityService._();

  static const Duration probeTimeout = Duration(seconds: 2);
  static const Duration refreshInterval = Duration(seconds: 15);

  final Connectivity _connectivity = Connectivity();
  final StreamController<NetworkReachabilitySnapshot> _controller =
      StreamController<NetworkReachabilitySnapshot>.broadcast();
  final StreamController<void> _connectionAvailable =
      StreamController<void>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _refreshTimer;
  int _startCount = 0;
  NetworkReachabilitySnapshot _latest = const NetworkReachabilitySnapshot(
    state: NetworkReachabilityState.checking,
  );
  Future<NetworkReachabilitySnapshot>? _refreshFuture;

  /// Returns snapshots.
  Stream<NetworkReachabilitySnapshot> get snapshots => _controller.stream;

  /// An interface became available. Time-sensitive work can try its own server
  /// request immediately while the shared DNS probe runs separately.
  Stream<void> get connectionAvailable => _connectionAvailable.stream;

  /// Returns latest.
  NetworkReachabilitySnapshot get latest => _latest;

  // NetworkReachabilityService.start reference-counts listeners so shared screens reuse one
  // connectivity monitor.
  /// Starts.
  Future<void> start() async {
    _startCount += 1;
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen(
      (connections) {
        if (connections.any((result) => result != ConnectivityResult.none)) {
          _connectionAvailable.add(null);
        }
        unawaited(refresh());
      },
      onError: (Object error, StackTrace stackTrace) {
        _emit(
          const NetworkReachabilitySnapshot(
            state: NetworkReachabilityState.offline,
            message: 'Unable to monitor network changes.',
          ),
        );
      },
    );
    _refreshTimer ??= Timer.periodic(refreshInterval, (_) {
      unawaited(refresh());
    });
    await refresh();
  }

  /// Stops.
  Future<void> stop() async {
    if (_startCount > 0) {
      _startCount -= 1;
    }
    if (_startCount > 0) {
      return;
    }
    final subscription = _connectivitySubscription;
    _connectivitySubscription = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await subscription?.cancel();
  }

  // refresh coalesces concurrent probes instead of starting a request for every listening widget.
  /// Refreshes.
  Future<NetworkReachabilitySnapshot> refresh() {
    return _refreshFuture ??= _refreshNow();
  }

  /// Refreshes now.
  Future<NetworkReachabilitySnapshot> _refreshNow() async {
    try {
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.isEmpty ||
          connectivity.every((result) => result == ConnectivityResult.none)) {
        return _emit(
          const NetworkReachabilitySnapshot(
            state: NetworkReachabilityState.offline,
            message: 'No active network connection.',
          ),
        );
      }

      final lookup = await InternetAddress.lookup(
        'firestore.googleapis.com',
      ).timeout(probeTimeout);
      final canResolve = lookup.any((address) => address.rawAddress.isNotEmpty);
      if (!canResolve) {
        return _emit(
          const NetworkReachabilitySnapshot(
            state: NetworkReachabilityState.offline,
            message: 'Internet DNS is not reachable.',
          ),
        );
      }

      return _emit(
        const NetworkReachabilitySnapshot(
          state: NetworkReachabilityState.online,
        ),
      );
    } on TimeoutException {
      return _emit(
        const NetworkReachabilitySnapshot(
          state: NetworkReachabilityState.offline,
          message: 'Internet check timed out.',
        ),
      );
    } catch (_) {
      return _emit(
        const NetworkReachabilitySnapshot(
          state: NetworkReachabilityState.offline,
          message: 'Internet is not reachable.',
        ),
      );
    } finally {
      _refreshFuture = null;
    }
  }

  /// Computes emit.
  NetworkReachabilitySnapshot _emit(NetworkReachabilitySnapshot snapshot) {
    _latest = snapshot;
    if (!_controller.isClosed) {
      _controller.add(snapshot);
    }
    return snapshot;
  }
}
