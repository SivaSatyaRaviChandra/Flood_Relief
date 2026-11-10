/// Device identity management.
///
/// Persists a unique device ID once and reuses it for the lifetime of the
/// application. A fresh ID is never generated per launch.
library;

import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/id_generator.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.createdAt});

  final String deviceId;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        DeviceKeys.deviceId: deviceId,
        if (createdAt != null) DeviceKeys.createdAt: createdAt!.toIso8601String(),
      };
}

class DeviceIdentityService {
  DeviceIdentityService(this._box, this._idGenerator);

  final Box _box;
  final IdGenerator _idGenerator;

  /// Returns the persisted identity, creating and persisting it on first use.
  DeviceIdentity getOrCreate() {
    final existing = _box.get(DeviceKeys.deviceId);
    if (existing is String && existing.isNotEmpty) {
      return DeviceIdentity(
        deviceId: existing,
        createdAt:
            DateTime.tryParse(_box.get(DeviceKeys.createdAt)?.toString() ?? ''),
      );
    }
    final identity = DeviceIdentity(
      deviceId: _idGenerator.deviceId(),
      createdAt: DateTime.now().toUtc(),
    );
    _box.putAll(identity.toMap());
    return identity;
  }
}