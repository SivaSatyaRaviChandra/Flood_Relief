/// Multi-hop store-and-forward routing.
///
/// When a packet arrives it is:
///  1. validated by the codec;
///  2. checked against the bounded duplicate cache;
///  3. stored;
///  4. forwarded (hop +1, TTL -1) when it still has TTL;
///  5. otherwise dropped with a reason.
///
/// Loops cannot form because duplicates are dropped. Replay and TTL limits
/// are enforced.
library;

import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../models/sos_packet.dart';
import '../ble/acknowledgement_service.dart';
import '../ble/ble_transport.dart';
import '../ble/packet_codec.dart';
import '../ble/transmission_queue.dart';
import '../../repositories/packet_repository.dart';

enum RoutingDecision {
  acceptedForwarded,
  acceptedNotForwarded,
  duplicate,
  invalidPacket,
  replayRejected,
  ttlExpired,
  dropFailedForward,
  outgoingQueued,
}

class RoutingEvent {
  const RoutingEvent({
    required this.decision,
    required this.detail,
    required this.at,
    this.sosId,
    this.packetId,
  });

  final RoutingDecision decision;
  final String detail;
  final DateTime at;
  final String? sosId;
  final String? packetId;
}

class PacketRouter {
  PacketRouter({
    required this.packetRepository,
    required this.codec,
    required this.transport,
    required this.queue,
    required this.nodeDeviceId,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final PacketRepository packetRepository;
  final PacketCodec codec;
  final BleTransport transport;
  final TransmissionQueue queue;
  final String nodeDeviceId;
  final DateTime Function() _now;

  /// Attached by the wiring layer after construction (avoids a constructor
  /// cycle between router and acknowledgement service).
  AcknowledgementService? ackService;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final _events = StreamController<RoutingEvent>.broadcast();
  Stream<RoutingEvent> get events => _events.stream;

  /// Handle a raw payload from the link layer.
  Future<RoutingDecision> routeIncoming(String raw) async {
    BlePacketMessage message;
    try {
      message = codec.decode(raw);
    } on PacketValidationError catch (e) {
      _emit(
        RoutingDecision.invalidPacket,
        e.reason,
      );
      return RoutingDecision.invalidPacket;
    }
    return routeValidated(message);
  }

  /// Handle a message that has already been decoded and validated.
  Future<RoutingDecision> routeValidated(BlePacketMessage message) async {
    // 1. duplicate detection
    final seen = await packetRepository.isDuplicate(message.packetId);
    await packetRepository.recordSeen(message.packetId, _now());

    if (seen) {
      _emit(
        RoutingDecision.duplicate,
        'Duplicate packet ${message.packetId} — dropped.',
        message,
      );
      return RoutingDecision.duplicate;
    }

    // 2. store the packet
    await packetRepository.savePacket(message);

    // 3. semantic handling (ACK matching / ACK generation)
    if (message is AckPacketMessage) {
      await ackService?.handleAck(message);
    }
    if (message is SosPacketMessage) {
      await ackService?.handleSos(message);
    }

    // 4. store-and-forward
    final hop = message.hopCount + 1;
    final ttl = message.ttl - 1;
    if (hop > BleConstants.maxHops || ttl <= 0) {
      _emit(
        RoutingDecision.ttlExpired,
        'TTL exhausted for ${message.packetId} (hop $hop) — not forwarded.',
        message,
      );
      return RoutingDecision.ttlExpired;
    }

    final forwarded = message.copyWith(
      senderDeviceId: nodeDeviceId,
      hopCount: hop,
      ttl: ttl,
    );
    try {
      await transport.broadcast(codec.encode(forwarded));
      await packetRepository.savePacket(forwarded);
      _emit(
        RoutingDecision.acceptedForwarded,
        'Forwarded ${message.packetId}: hop $hop, TTL $ttl.',
        message,
      );
      return RoutingDecision.acceptedForwarded;
    } catch (_) {
      _emit(
        RoutingDecision.dropFailedForward,
        'Forwarding failed for ${message.packetId} (no reachable peer).',
        message,
      );
      return RoutingDecision.dropFailedForward;
    }
  }

  /// Route a message originating on this device (queue + broadcast).
  Future<void> routeOutgoing(BlePacketMessage message) async {
    await packetRepository.recordSeen(message.packetId, _now());
    await packetRepository.savePacket(message);
    await queue.enqueue(message);
    _emit(
      RoutingDecision.outgoingQueued,
      'Queued outgoing ${message.packetId}.',
      message,
    );
  }

  void _emit(
    RoutingDecision decision,
    String detail, [
    BlePacketMessage? packet,
  ]) {
    if (_events.isClosed) return;
    _events.add(RoutingEvent(
      decision: decision,
      detail: detail,
      at: _now(),
      sosId: packet?.sosId,
      packetId: packet?.packetId,
    ));
  }

  Future<void> dispose() async {
    await _events.close();
  }
}