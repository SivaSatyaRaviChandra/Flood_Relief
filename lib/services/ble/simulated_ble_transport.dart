/// Simulated BLE layer.
///
/// This is an in-process radio emulator used for development, demos and
/// automated tests. It implements the same [BleTransport] interface as the
/// real BLE transport, so the entire SOS → relay → relay → rescue workflow
/// can be demonstrated on a single device.
///
/// The simulation lives here, never inside the real BLE classes.
library;

import 'dart:async';

import '../ble/ble_transport.dart';

/// Registry of simulated nodes and their radio reachability.
class SimulatedMesh {
  final Map<String, SimulatedBleTransport> _nodes = {};
  final Map<String, Set<String>> _links = {};
  Duration latency = const Duration(milliseconds: 250);

  void register(SimulatedBleTransport node) {
    _nodes[node.localDeviceId] = node;
    _links.putIfAbsent(node.localDeviceId, () => <String>{});
  }

  void unregister(String deviceId) {
    _nodes.remove(deviceId);
    _links.remove(deviceId);
  }

  /// Undirected link: if A can reach B then B can reach A.
  void addLink(String a, String b) {
    _links.putIfAbsent(a, () => <String>{}).add(b);
    _links.putIfAbsent(b, () => <String>{}).add(a);
  }

  List<String> neighbors(String deviceId) =>
      _links[deviceId]?.toList() ?? const <String>[];

  Future<void> transmit(SimulatedBleTransport from, String payload) async {
    final targets = neighbors(from.localDeviceId);
    if (targets.isEmpty) return;
    for (final targetId in targets) {
      final node = _nodes[targetId];
      if (node == null) continue;
      await node._receive(payload, from.localDeviceId);
    }
  }

  /// Inject a packet as if it arrived from [fromDeviceId] directly at
  /// [targetDeviceId]. Used by demo controls to simulate an inbound packet
  /// without a real outbound transmission.
  Future<void> inject(String targetDeviceId, String payload,
      String fromDeviceId) async {
    final node = _nodes[targetDeviceId];
    if (node == null) return;
    await node._receive(payload, fromDeviceId);
  }
}

/// A single simulated node: a full [BleTransport] backed by [SimulatedMesh].
class SimulatedBleTransport implements BleTransport {
  SimulatedBleTransport({
    required this.mesh,
    required this.localDeviceId,
    this.linkLatency = const Duration(milliseconds: 250),
  }) {
    mesh.register(this);
  }

  final SimulatedMesh mesh;
  @override
  final String localDeviceId;
  final Duration linkLatency;

  final _state = StreamController<BleTransportState>.broadcast();
  final _incoming = StreamController<ReceivedPacket>.broadcast();

  @override
  Stream<BleTransportState> get state => _state.stream;

  @override
  Stream<ReceivedPacket> get incoming => _incoming.stream;

  @override
  Future<void> start({bool requestPermissions = false}) async {
    if (!_state.isClosed) _state.add(BleTransportState.advertising);
  }

  @override
  Future<void> stop() async {
    if (!_state.isClosed) _state.add(BleTransportState.idle);
  }

  Future<void> _receive(String payload, String fromDeviceId) async {
    await Future<void>.delayed(linkLatency);
    if (_incoming.isClosed) return;
    _incoming.add(ReceivedPacket(
      payload: payload,
      fromDeviceId: fromDeviceId,
      receivedAt: DateTime.now().toUtc(),
    ));
  }

  @override
  Future<void> broadcast(String payload) async {
    if (!_state.isClosed) _state.add(BleTransportState.connected);
    await mesh.transmit(this, payload);
  }

  @override
  Future<void> dispose() async {
    mesh.unregister(localDeviceId);
    await _state.close();
    await _incoming.close();
  }
}