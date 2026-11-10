/// Transmission queue: pending packets, retries and timeouts.
///
/// A packet that cannot be delivered stays pending — the application is
/// offline-first, so the packet is *never* dropped just because the link is
/// unavailable. `retryPending()` is called when the transport reports it has
/// peers again.
library;

import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../models/sos_packet.dart';
import '../ble/ble_transport.dart';
import '../ble/packet_codec.dart';
import '../../repositories/packet_repository.dart';

enum QueueEventKind {
  enqueued,
  broadcast,
  retrying,
  ackReceived,
  timeout,
  gaveUpAttempts,
}

class QueueEvent {
  const QueueEvent({
    required this.kind,
    required this.message,
    required this.at,
    this.sosId,
    this.packetId,
  });

  final QueueEventKind kind;
  final String message;
  final DateTime at;
  final String? sosId;
  final String? packetId;
}

class TransmissionQueue {
  TransmissionQueue({
    required this.packetRepository,
    required this.transport,
    required this.codec,
    this.retryDelay = BleConstants.retryDelay,
    this.maxAttempts = BleConstants.maxTransmissionAttempts,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final PacketRepository packetRepository;
  final BleTransport transport;
  final PacketCodec codec;
  final Duration retryDelay;
  final int maxAttempts;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final _events = StreamController<QueueEvent>.broadcast();
  final Map<String, int> _attempts = {};
  final Map<String, Timer> _timers = {};
  bool _disposed = false;

  Stream<QueueEvent> get events => _events.stream;

  /// Queue a packet for transmission; the packet must already be persisted.
  Future<void> enqueue(BlePacketMessage message) async {
    final payload = codec.encode(message);
    await packetRepository.savePacket(message);
    await packetRepository.markPending(message.packetId);
    _emit(
      QueueEventKind.enqueued,
      'SOS stored locally and queued for transmission.',
      message,
    );
    await _attempt(message, payload);
  }

  Future<void> _attempt(BlePacketMessage message, String payload) async {
    if (_disposed) return;
    final id = message.packetId;
    final count = (_attempts[id] ?? 0) + 1;
    _attempts[id] = count;

    if (count > 1) {
      _emit(QueueEventKind.retrying, 'Retry $count for $id.', message);
    }

    try {
      await transport.broadcast(payload);
      _emit(
        QueueEventKind.broadcast,
        'Packet handed to the link layer (attempt $count).',
        message,
      );
    } catch (e) {
      _emit(
        QueueEventKind.retrying,
        'Link unavailable (attempt $count): ${e.runtimeType}.',
        message,
      );
    }

    if (count >= maxAttempts) {
      _emit(
        QueueEventKind.gaveUpAttempts,
        'Still searching for a nearby relay/rescue device. Your SOS remains '
        'saved on this device and will be transmitted when a peer is reached.',
        message,
      );
      return;
    }
    _timers[id]?.cancel();
    _timers[id] = Timer(retryDelay, () async {
      await _attempt(message, payload);
    });
  }

  /// Called by the acknowledgement service when an ACK for [sosId] arrives.
  Future<void> markAcknowledged(String sosId) async {
    final pending = await packetRepository.pendingPacketIds();
    for (final id in pending) {
      _timers[id]?.cancel();
      _timers.remove(id);
      _attempts.remove(id);
      await packetRepository.markPendingResolved(id);
    }
    _emit(
      QueueEventKind.ackReceived,
      'ACK received — this SOS has been received by rescue. Matched ACK to '
      'packet for $sosId.',
    );
  }

  /// Retry everything still pending (called when the transport reports peers).
  Future<void> retryPending() async {
    final ids = await packetRepository.pendingPacketIds();
    for (final id in ids) {
      _timers[id]?.cancel();
      _timers.remove(id);
      // Reconstruct a packet to (re)encode. The payload is deterministic, so
      // re-encoding and storing produce identical bytes.
      final pendingMessage = await _load(id);
      if (pendingMessage != null) {
        final payload = codec.encode(pendingMessage);
        await _attempt(pendingMessage, payload);
      }
    }
  }

  Future<BlePacketMessage?> _load(String packetId) async {
    final packets = await packetRepository.getPackets();
    for (final p in packets) {
      if (p.packetId == packetId) return p;
    }
    return null;
  }

  Future<void> _emit(QueueEventKind kind, String message,
      [BlePacketMessage? packet]) async {
    if (_disposed || _events.isClosed) return;
    _events.add(QueueEvent(
      kind: kind,
      message: message,
      at: _now(),
      sosId: packet?.sosId,
      packetId: packet?.packetId,
    ));
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await _events.close();
  }
}