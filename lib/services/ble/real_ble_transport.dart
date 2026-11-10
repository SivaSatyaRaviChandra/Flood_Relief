/// Real BLE transport (`bluetooth_low_energy` 6.x).
///
/// Each device runs as a *peripheral* (advertises a FloodRelief GATT service
/// so peers can connect and write packets to it) and as a *central* (scans
/// for FloodRelief peers, connects, and writes/notifies packets).
///
/// RELIABILITY NOTES (honest): BLE range is typically tens of metres indoors
/// and up to ~100 m outdoors under good conditions; walls, interference and
/// OS power policies all reduce this. This transport implements single-hop
/// *link* delivery — multi-hop behaviour comes from the router layer on top.
/// Multi-device behaviour has been validated in the simulated mesh; physical
/// device testing is listed as a known limitation in the README.
///
/// Permissions are never requested during cold start (see [requestPermissions]
/// and `start(requestPermissions:)`); they are requested from user actions
/// such as sending an SOS or explicitly enabling the link.
library;

import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import '../../core/constants/app_constants.dart';
import 'ble_transport.dart';

class _PeerLink {
  _PeerLink(this.peripheral, this.characteristic);
  final Peripheral peripheral;
  final GATTCharacteristic characteristic;
  DateTime lastActivity = DateTime.now().toUtc();
}

class RealBleTransport implements BleTransport {
  RealBleTransport({required this.localDeviceId});

  @override
  final String localDeviceId;

  final _state = StreamController<BleTransportState>.broadcast();
  final _incoming = StreamController<ReceivedPacket>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  late final PeripheralManager _peripheralManager;
  late final CentralManager _centralManager;

  GATTCharacteristic? _txCharacteristic;
  final Map<String, Central> _connectedCentrals = {};
  final Map<String, _PeerLink> _peripheralLinks = {};
  final Map<String, Peripheral> _discoveredPeers = {};

  Timer? _maintenanceTimer;
  bool _started = false;

  String get _advertisedName => '${BleConstants.deviceNamePrefix}$localDeviceId';

  @override
  Stream<BleTransportState> get state => _state.stream;

  @override
  Stream<ReceivedPacket> get incoming => _incoming.stream;

  /// Requests the Android 12+ Bluetooth runtime permissions the link needs.
  /// Returns true only when both sides are usable. Safe to call at any point;
  /// it is a no-op when permissions are already granted.
  Future<bool> requestPermissions() async {
    var ok = true;
    try {
      ok = await _centralManager.authorize() && ok;
    } catch (_) {}
    try {
      ok = await _peripheralManager.authorize() && ok;
    } catch (_) {}
    return ok;
  }

  @override
  Future<void> start({bool requestPermissions = false}) async {
    if (_started) return;
    _started = true;
    _publish(BleTransportState.starting);

    _peripheralManager = PeripheralManager();
    _centralManager = CentralManager();

    try {
      if (requestPermissions) {
        await this.requestPermissions();
      }

      _subscriptions
        ..add(_peripheralManager.characteristicWriteRequested.listen(
          _handleCentralWrite,
        ))
        ..add(_peripheralManager.connectionStateChanged.listen(
          _handleCentralConnectionChanged,
        ))
        ..add(_centralManager.discovered.listen(_handleDiscovered))
        ..add(_centralManager.connectionStateChanged.listen(
          _handlePeripheralConnectionChanged,
        ))
        ..add(_centralManager.characteristicNotified.listen(
          _handleNotification,
        ));

      final serviceUuid = UUID.fromString(BleConstants.serviceUuid);
      final characteristicUuid =
          UUID.fromString(BleConstants.characteristicUuid);

      final characteristic = GATTCharacteristic.mutable(
        uuid: characteristicUuid,
        properties: const [
          GATTCharacteristicProperty.read,
          GATTCharacteristicProperty.write,
          GATTCharacteristicProperty.writeWithoutResponse,
          GATTCharacteristicProperty.notify,
        ],
        permissions: const [
          GATTCharacteristicPermission.read,
          GATTCharacteristicPermission.write,
        ],
        descriptors: const [],
      );

      await _peripheralManager.addService(GATTService(
        uuid: serviceUuid,
        isPrimary: true,
        includedServices: const [],
        characteristics: [characteristic],
      ));
      _txCharacteristic = characteristic;

      await _peripheralManager.startAdvertising(Advertisement(
        name: _advertisedName,
        serviceUUIDs: [serviceUuid],
      ));

      await _centralManager.startDiscovery(serviceUUIDs: [serviceUuid]);
      _publish(BleTransportState.advertising);

      _maintenanceTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _cleanupIdleLinks(),
      );
    } catch (_) {
      _started = false;
      _publish(BleTransportState.error);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Peripheral side (peers write packets to us)
  // ---------------------------------------------------------------------------

  Future<void> _handleCentralWrite(
    GATTCharacteristicWriteRequestedEventArgs event,
  ) async {
    try {
      await _peripheralManager.respondWriteRequest(event.request);
    } catch (_) {
      // Already answered by the platform or a no-response write.
    }
    final payload = utf8.decode(event.request.value, allowMalformed: true);
    _incoming.add(ReceivedPacket(
      payload: payload,
      fromDeviceId: event.central.uuid.toString(),
      receivedAt: DateTime.now().toUtc(),
    ));
  }

  void _handleCentralConnectionChanged(
    CentralConnectionStateChangedEventArgs event,
  ) {
    final id = event.central.uuid.toString();
    if (event.state == ConnectionState.connected) {
      _connectedCentrals[id] = event.central;
    } else {
      _connectedCentrals.remove(id);
    }
    _recomputeState();
  }

  // ---------------------------------------------------------------------------
  // Central side (we connect to peers and write packets to them)
  // ---------------------------------------------------------------------------

  Future<void> _handleDiscovered(DiscoveredEventArgs event) async {
    final peripheralId = event.peripheral.uuid.toString();
    final name = _safeName(event.advertisement);
    if (name == _advertisedName) return; // never connect to ourselves
    if (_peripheralLinks.containsKey(peripheralId)) return;
    if (_discoveredPeers.containsKey(peripheralId)) return;
    _discoveredPeers[peripheralId] = event.peripheral;

    try {
      await _centralManager.connect(event.peripheral);
      await _setupLink(event.peripheral);
    } catch (_) {
      _discoveredPeers.remove(peripheralId);
    }
  }

  String? _safeName(Advertisement advertisement) {
    try {
      return advertisement.name;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setupLink(Peripheral peripheral) async {
    final peripheralId = peripheral.uuid.toString();
    List<GATTService> services;
    try {
      services = await _centralManager.discoverGATT(peripheral);
    } catch (_) {
      _discoveredPeers.remove(peripheralId);
      return;
    }

    GATTCharacteristic? target;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid ==
            UUID.fromString(BleConstants.characteristicUuid)) {
          target = characteristic;
        }
      }
    }
    if (target == null) {
      try {
        await _centralManager.disconnect(peripheral);
      } catch (_) {}
      _discoveredPeers.remove(peripheralId);
      return;
    }

    _peripheralLinks[peripheralId] = _PeerLink(peripheral, target);
    try {
      await _centralManager.setCharacteristicNotifyState(
        peripheral,
        target,
        state: true,
      );
    } catch (_) {
      // Notifications are best-effort; writes still work.
    }
    _recomputeState();
  }

  void _handlePeripheralConnectionChanged(
    PeripheralConnectionStateChangedEventArgs event,
  ) {
    final peripheralId = event.peripheral.uuid.toString();
    if (event.state == ConnectionState.disconnected) {
      _peripheralLinks.remove(peripheralId);
      _discoveredPeers.remove(peripheralId);
      _recomputeState();
    }
  }

  Future<void> _handleNotification(
    GATTCharacteristicNotifiedEventArgs event,
  ) async {
    final payload = utf8.decode(event.value, allowMalformed: true);
    _incoming.add(ReceivedPacket(
      payload: payload,
      fromDeviceId: event.peripheral.uuid.toString(),
      receivedAt: DateTime.now().toUtc(),
    ));
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  @override
  Future<void> broadcast(String payload) async {
    final bytes = utf8.encode(payload);
    var handedOff = false;

    for (final central in _connectedCentrals.values) {
      final characteristic = _txCharacteristic;
      if (characteristic == null) break;
      try {
        await _peripheralManager.notifyCharacteristic(
          central,
          characteristic,
          value: bytes,
        );
        handedOff = true;
      } catch (_) {
        // Central not subscribed (yet) — other paths may still deliver.
      }
    }

    for (final link in _peripheralLinks.values) {
      try {
        await _centralManager.writeCharacteristic(
          link.peripheral,
          link.characteristic,
          value: bytes,
          type: GATTCharacteristicWriteType.withResponse,
        );
        link.lastActivity = DateTime.now().toUtc();
        handedOff = true;
      } catch (_) {
        // Peer unreachable right now; the queue will retry.
      }
    }

    if (handedOff) {
      _publish(BleTransportState.connected);
    } else {
      throw StateError('No reachable BLE peer for payload delivery.');
    }
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  void _cleanupIdleLinks() {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    final stale = <String>[];
    _peripheralLinks.forEach((id, link) {
      if (link.lastActivity.isBefore(cutoff)) stale.add(id);
    });
    for (final id in stale) {
      final link = _peripheralLinks.remove(id);
      if (link == null) continue;
      _centralManager.disconnect(link.peripheral).catchError((Object _) {});
    }
    if (stale.isNotEmpty) _recomputeState();
  }

  void _recomputeState() {
    if (_connectedCentrals.isNotEmpty || _peripheralLinks.isNotEmpty) {
      _publish(BleTransportState.connected);
    } else if (_started) {
      _publish(BleTransportState.advertising);
    }
  }

  void _publish(BleTransportState value) {
    if (_state.isClosed) return;
    _state.add(value);
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _peripheralManager.stopAdvertising();
    } catch (_) {}
    try {
      await _centralManager.stopDiscovery();
    } catch (_) {}
    for (final link in _peripheralLinks.values) {
      try {
        await _centralManager.disconnect(link.peripheral);
      } catch (_) {}
    }
    _peripheralLinks.clear();
    _discoveredPeers.clear();
    _connectedCentrals.clear();
    _publish(BleTransportState.idle);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _state.close();
    await _incoming.close();
  }
}