/// BLE transport boundary.
///
/// Both the real BLE transport and the in-device simulated mesh implement
/// this interface. The rest of the application only depends on [BleTransport],
/// which is why multi-hop *routing* (not the radio layer) carries the mesh
/// intelligence.
library;

enum BleTransportState {
  idle,
  starting,
  advertising,
  scanning,
  connected,
  error,
}

class ReceivedPacket {
  const ReceivedPacket({
    required this.payload,
    required this.fromDeviceId,
    required this.receivedAt,
  });

  final String payload;
  final String fromDeviceId;
  final DateTime receivedAt;
}

abstract class BleTransport {
  String get localDeviceId;

  Stream<BleTransportState> get state;

  /// Raw payloads received from the link layer.
  Stream<ReceivedPacket> get incoming;

  /// Bring the link layer up. [requestPermissions] is only ever true when
  /// called from an explicit user action (sending an SOS or enabling the
  /// link), never from a cold start.
  Future<void> start({bool requestPermissions = false});
  Future<void> stop();

  /// Hand a payload to the link layer for delivery to reachable peers.
  Future<void> broadcast(String payload);

  Future<void> dispose();
}