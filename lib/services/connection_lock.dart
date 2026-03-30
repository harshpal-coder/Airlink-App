import '../utils/connectivity_logger.dart';

/// UUID-scoped connection lock.
///
/// Guarantees that at most one [requestConnection] call is in-flight
/// per device UUID at any time. This is the primary guard against
/// duplicate connection attempts when [onEndpointFound] and
/// [ReconnectionManager._attemptReconnect] fire concurrently for the
/// same peer.
///
/// Usage:
/// ```dart
/// if (!ConnectionLock.acquire(uuid)) return; // already in-flight
/// try {
///   await Nearby().requestConnection(...);
/// } finally {
///   ConnectionLock.release(uuid);
/// }
/// ```
class ConnectionLock {
  ConnectionLock._(); // private — singleton access only via static methods

  /// Set of UUIDs currently holding a connection lock.
  static final Set<String> _locked = {};

  /// Attempt to acquire the lock for [uuid].
  ///
  /// Returns `true` if the lock was granted (no other caller holds it).
  /// Returns `false` if the UUID is already being connected — the caller
  /// should abort and not fire another [requestConnection].
  static bool acquire(String uuid) {
    if (_locked.contains(uuid)) {
      ConnectivityLogger.debug(
        LogCategory.connection,
        '[ConnectionLock] Lock DENIED for $uuid — already connecting',
      );
      return false;
    }
    _locked.add(uuid);
    ConnectivityLogger.debug(
      LogCategory.connection,
      '[ConnectionLock] Lock ACQUIRED for $uuid (locked: ${_locked.length})',
    );
    return true;
  }

  /// Release the lock for [uuid].
  ///
  /// Safe to call even if no lock was held — it is a no-op in that case.
  static void release(String uuid) {
    final removed = _locked.remove(uuid);
    if (removed) {
      ConnectivityLogger.debug(
        LogCategory.connection,
        '[ConnectionLock] Lock RELEASED for $uuid (locked: ${_locked.length})',
      );
    }
  }

  /// Force-release ALL locks. Use only during full radio restart / dispose.
  static void releaseAll() {
    final count = _locked.length;
    _locked.clear();
    ConnectivityLogger.info(
      LogCategory.connection,
      '[ConnectionLock] All $count lock(s) force-released (radio restart)',
    );
  }

  /// Returns `true` if the given UUID is currently locked.
  static bool isLocked(String uuid) => _locked.contains(uuid);

  /// Debug: number of currently held locks.
  static int get heldCount => _locked.length;
}
