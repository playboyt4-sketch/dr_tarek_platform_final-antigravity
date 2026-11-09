import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Process-wide source of the persistent device binding id.
///
/// Device binding (`onLoginAttempt`) and FCM token registration
/// (`onDeviceTokenRefresh`) must observe the exact same id. Concurrent
/// callers share one in-flight read/create, so two starts during the same
/// login cannot generate two different UUIDs.
class DeviceIdentityStore {
  /// Canonical id used by the backend device registry.
  static const canonicalKey = 'device_id_uuidv4';

  /// Legacy key kept mirrored so older readers resolve the same id.
  static const legacyKey = 'device_binding_device_id';

  final FlutterSecureStorage storage;
  final Uuid uuid;

  const DeviceIdentityStore({
    this.storage = const FlutterSecureStorage(),
    this.uuid = const Uuid(),
  });

  static Future<String>? _inFlight;

  /// Returns the install's device id, creating and persisting it once.
  Future<String> getOrCreate() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _readOrCreate();
    _inFlight = future;

    // Do not cache a failed keychain read forever: the next login can retry.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_inFlight, future)) _inFlight = null;
        },
      ),
    );

    return future;
  }

  Future<String> _readOrCreate() async {
    String? id = await storage.read(key: canonicalKey);
    if (id == null || id.isEmpty) {
      id = await storage.read(key: legacyKey);
    }
    if (id == null || id.isEmpty) {
      id = uuid.v4();
    }
    await storage.write(key: canonicalKey, value: id);
    await storage.write(key: legacyKey, value: id);
    return id;
  }

  @visibleForTesting
  static void resetCacheForTests() {
    _inFlight = null;
  }
}
