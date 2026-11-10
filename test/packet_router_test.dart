/// Multi-hop store-and-forward routing: accept, forward, duplicate and TTL.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/sos_packet.dart';
import 'package:flood_relief/repositories/packet_repository.dart';
import 'package:flood_relief/services/ble/packet_codec.dart';
import 'package:flood_relief/services/ble/packet_router.dart';
import 'package:flood_relief/services/ble/transmission_queue.dart';

import 'helpers/fakes.dart';

final DateTime fixedNow = DateTime.utc(2026, 9, 22, 12, 0, 0);

SosPacketMessage _packet({int ttl = 8, int hop = 0, String? packetId}) {
  return SosPacketMessage(
    packetId: packetId ?? 'PKT-ABCD1234',
    sosId: 'SOS-20260922-ABCDEF',
    originDeviceId: 'DEVICE-ORIG1234',
    senderDeviceId: 'DEVICE-ORIG1234',
    hopCount: hop,
    ttl: ttl,
    timestamp: fixedNow,
    latitude: 17.7,
    longitude: 83.3,
    accuracy: 12.0,
    totalPeople: 3,
    childrenCount: 1,
    elderlyCount: 0,
    pregnantWomenCount: 0,
    specialAssistanceCount: 0,
    emergencyType: EmergencyType.rescueRequired,
    description: 'Water rising.',
    priority: SosPriority.high,
  );
}

void main() {
  late MemoryPacketRepository packets;
  late RecordingTransport transport;
  late PacketRouter router;

  PacketRouter buildRouter({String nodeId = 'DEVICE-NODE'}) {
    packets = MemoryPacketRepository();
    transport = RecordingTransport(nodeId: nodeId);
    final codec = PacketCodec(now: () => fixedNow);
    final queue = TransmissionQueue(
      packetRepository: packets,
      transport: transport,
      codec: codec,
      maxAttempts: 1,
      retryDelay: const Duration(seconds: 1),
    );
    return PacketRouter(
      packetRepository: packets,
      codec: codec,
      transport: transport,
      queue: queue,
      nodeDeviceId: nodeId,
      now: () => fixedNow,
    );
  }

  test('a fresh packet is stored and forwarded with hop+1 / ttl-1', () async {
    router = buildRouter();
    final decision = await router.routeValidated(_packet());

    expect(decision, RoutingDecision.acceptedForwarded);
    expect(transport.sent, hasLength(1));

    final stored = await packets.getPackets();
    // The store is keyed by packetId, so the forwarded copy replaces the
    // original — a single record reflects the latest hop.
    expect(stored, hasLength(1));
    final forwarded = stored.single;
    expect(forwarded.senderDeviceId, 'DEVICE-NODE');
    expect(forwarded.hopCount, 1);
    expect(forwarded.ttl, 7);
  });

  test('routeIncoming decodes then stores and forwards', () async {
    router = buildRouter();
    final encoded = router.codec.encode(_packet());
    final decision = await router.routeIncoming(encoded);
    expect(decision, RoutingDecision.acceptedForwarded);
    expect(transport.sent, hasLength(1));
  });

  test('duplicates are dropped without forwarding', () async {
    router = buildRouter();
    final packet = _packet();
    await router.routeValidated(packet);
    expect(transport.sent, hasLength(1));

    final decision = await router.routeValidated(packet);
    expect(decision, RoutingDecision.duplicate);
    expect(transport.sent, hasLength(1)); // no second broadcast
  });

  test('exhausted TTL is not forwarded', () async {
    router = buildRouter();
    final decision = await router.routeValidated(_packet(ttl: 1));
    expect(decision, RoutingDecision.ttlExpired);
    expect(transport.sent, isEmpty);
  });

  test('unparseable payloads are rejected', () async {
    router = buildRouter();
    final decision = await router.routeIncoming('not json');
    expect(decision, RoutingDecision.invalidPacket);
    expect(transport.sent, isEmpty);
  });

  test('routeOutgoing queues the packet for transmission', () async {
    router = buildRouter();
    await router.routeOutgoing(_packet(packetId: 'PKT-OUT1000'));
    final pending = await packets.pendingPacketIds();
    expect(pending, contains('PKT-OUT1000'));
    expect(transport.sent, hasLength(1)); // one immediate attempt
  });

  test('routing events are broadcast to listeners', () async {
    router = buildRouter();
    final completer = Completer<RoutingDecision>();
    final sub = router.events.listen((e) {
      if (!completer.isCompleted) completer.complete(e.decision);
    });
    await router.routeValidated(_packet(packetId: 'PKT-EVNT001'));
    final decision = await completer.future.timeout(const Duration(seconds: 2));
    await sub.cancel();
    expect(decision, RoutingDecision.acceptedForwarded);
  });
}