/// Acknowledgement service: ACK generation, ACK reception and matching ACKs
/// to the originating SOS.
///
/// * Rescue nodes run with `autoAck = true`: every valid SOS they receive
///   triggers an ACK packet routed back through the mesh.
/// * The afflicted device matches returning ACKs and fires [onAckReceived].
///
/// "Your SOS has been received" is only ever shown after a real matched ACK.
library;

import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/utils/id_generator.dart';
import '../../models/sos_packet.dart';
import '../ble/packet_router.dart';

class AcknowledgementService {
  AcknowledgementService({
    required this.localDeviceId,
    required this.idGenerator,
    this.autoAck = false,
    this.ownsSos,
    this.onAckReceived,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final String localDeviceId;
  final IdGenerator idGenerator;

  /// When true this node answers SOS packets with ACKs (rescue role).
  final bool autoAck;

  /// Whether this device originated [sosId] (async lookup to the store).
  final Future<bool> Function(String sosId)? ownsSos;

  /// Called once when an ACK for a SOS owned by this device is matched.
  final Future<void> Function(String sosId)? onAckReceived;

  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  PacketRouter? _router;

  final Set<String> _acknowledgedSosIds = {};

  final _ackEvents = StreamController<String>.broadcast();
  Stream<String> get ackEvents => _ackEvents.stream;

  void attachRouter(PacketRouter router) {
    _router = router;
  }

  bool hasAcknowledged(String sosId) => _acknowledgedSosIds.contains(sosId);

  /// Called by the router for every valid incoming SOS packet.
  Future<void> handleSos(SosPacketMessage message) async {
    if (!autoAck) return;
    if (_acknowledgedSosIds.contains(message.sosId)) return;
    _acknowledgedSosIds.add(message.sosId);

    final ack = AckPacketMessage(
      packetId: idGenerator.ackId(message.sosId),
      sosId: message.sosId,
      originDeviceId: localDeviceId,
      senderDeviceId: localDeviceId,
      hopCount: 0,
      ttl: BleConstants.defaultTtl,
      timestamp: _now().toUtc(),
      latitude: message.latitude,
      longitude: message.longitude,
      accuracy: message.accuracy,
    );
    await _router?.routeOutgoing(ack);
  }

  /// Called by the router for every valid incoming ACK packet.
  Future<void> handleAck(AckPacketMessage ack) async {
    final owns = await (ownsSos?.call(ack.sosId) ?? Future.value(false));
    if (!owns || _acknowledgedSosIds.contains(ack.sosId)) return;
    _acknowledgedSosIds.add(ack.sosId);
    if (!_ackEvents.isClosed) _ackEvents.add(ack.sosId);
    await onAckReceived?.call(ack.sosId);
  }
}