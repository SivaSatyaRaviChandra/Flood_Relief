/// Developer/demo mode controller.
///
/// Everything here is simulation machinery: relays B and C plus a rescue
/// node run inside the same process using the simulated mesh. No production
/// BLE class contains any of this logic.
library;

import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/demo/demo_data.dart';
import '../../core/utils/id_generator.dart';
import '../../models/enums/emergency_type.dart';
import '../../models/people_info.dart';
import '../../models/sos_packet.dart';
import '../../models/sos_request.dart';
import '../../repositories/packet_repository.dart';
import '../../repositories/sos_repository.dart';
import '../ble/acknowledgement_service.dart';
import '../ble/ble_transport.dart';
import '../ble/packet_codec.dart';
import '../ble/packet_router.dart';
import '../ble/simulated_ble_transport.dart';
import '../ble/transmission_queue.dart';
import '../sos_service.dart';

class DemoLogEntry {
  const DemoLogEntry({required this.message, required this.at});
  final String message;
  final DateTime at;
}

class DemoController {
  DemoController({
    required this.sosService,
    required this.sosRepository,
    required this.mesh,
    required this.mainTransport,
    required this.mainRouter,
    required this.mainDeviceId,
    required this.idGenerator,
    required this.codec,
    this.now,
  }) {
    _relayB = SimulatedBleTransport(
      mesh: mesh,
      localDeviceId: _relayBId,
      linkLatency: const Duration(milliseconds: 120),
    );
    _relayC = SimulatedBleTransport(
      mesh: mesh,
      localDeviceId: _relayCId,
      linkLatency: const Duration(milliseconds: 120),
    );
    _rescueNode = SimulatedBleTransport(
      mesh: mesh,
      localDeviceId: _rescueId,
      linkLatency: const Duration(milliseconds: 120),
    );

    final repoB = MemoryPacketRepository();
    final repoC = MemoryPacketRepository();
    final repoRescue = MemoryPacketRepository();

    _queueB = TransmissionQueue(
      packetRepository: repoB,
      transport: _relayB,
      codec: codec,
      retryDelay: const Duration(seconds: 3),
      maxAttempts: 2,
      now: now,
    );
    _queueC = TransmissionQueue(
      packetRepository: repoC,
      transport: _relayC,
      codec: codec,
      retryDelay: const Duration(seconds: 3),
      maxAttempts: 2,
      now: now,
    );
    _queueRescue = TransmissionQueue(
      packetRepository: repoRescue,
      transport: _rescueNode,
      codec: codec,
      retryDelay: const Duration(seconds: 3),
      maxAttempts: 2,
      now: now,
    );

    _ackB = AcknowledgementService(
      localDeviceId: _relayBId,
      idGenerator: idGenerator,
      autoAck: false,
      now: now,
    );
    _ackC = AcknowledgementService(
      localDeviceId: _relayCId,
      idGenerator: idGenerator,
      autoAck: false,
      now: now,
    );
    _ackRescue = AcknowledgementService(
      localDeviceId: _rescueId,
      idGenerator: idGenerator,
      autoAck: true,
      now: now,
    );

    _routerB = PacketRouter(
      packetRepository: repoB,
      codec: codec,
      transport: _relayB,
      queue: _queueB,
      nodeDeviceId: _relayBId,
      now: now,
    )..ackService = _ackB;
    _routerC = PacketRouter(
      packetRepository: repoC,
      codec: codec,
      transport: _relayC,
      queue: _queueC,
      nodeDeviceId: _relayCId,
      now: now,
    )..ackService = _ackC;
    _routerRescue = PacketRouter(
      packetRepository: repoRescue,
      codec: codec,
      transport: _rescueNode,
      queue: _queueRescue,
      nodeDeviceId: _rescueId,
      now: now,
    )..ackService = _ackRescue;
    _ackB.attachRouter(_routerB);
    _ackC.attachRouter(_routerC);
    _ackRescue.attachRouter(_routerRescue);
  }

  static const String _relayBId = 'DEVICE-DEMOB1';
  static const String _relayCId = 'DEVICE-DEMOC2';
  static const String _rescueId = 'DEVICE-RESCUE';

  final SosService sosService;
  final SosRepository sosRepository;
  final SimulatedMesh mesh;
  final BleTransport mainTransport;
  final PacketRouter mainRouter;
  final String mainDeviceId;
  final IdGenerator idGenerator;
  final PacketCodec codec;
  final DateTime Function()? now;
  late final DateTime Function() _now = now ?? _defaultNow;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  late final SimulatedBleTransport _relayB;
  late final SimulatedBleTransport _relayC;
  late final SimulatedBleTransport _rescueNode;
  late final PacketRouter _routerB;
  late final PacketRouter _routerC;
  late final PacketRouter _routerRescue;
  late final TransmissionQueue _queueB;
  late final TransmissionQueue _queueC;
  late final TransmissionQueue _queueRescue;
  late final AcknowledgementService _ackB;
  late final AcknowledgementService _ackC;
  late final AcknowledgementService _ackRescue;

  bool _meshStarted = false;

  final _events = StreamController<DemoLogEntry>.broadcast();
  Stream<DemoLogEntry> get events => _events.stream;

  bool get meshStarted => _meshStarted;

  void _wire(SimulatedBleTransport transport, PacketRouter router) {
    transport.incoming.listen((packet) {
      unawaited(router.routeIncoming(packet.payload));
    });
  }

  /// Bring up the A → B → C → Rescue simulated chain and start listening.
  Future<void> startMesh() async {
    if (_meshStarted) return;
    _meshStarted = true;

    mesh.addLink(mainDeviceId, _relayBId);
    mesh.addLink(_relayBId, _relayCId);
    mesh.addLink(_relayCId, _rescueId);

    _wire(_relayB, _routerB);
    _wire(_relayC, _routerC);
    _wire(_rescueNode, _routerRescue);

    await Future.wait([
      _relayB.start(),
      _relayC.start(),
      _rescueNode.start(),
    ]);

    _log(
      'Demo mesh running: [You] → $_relayBId → $_relayCId → '
      '$_rescueId. Send an SOS and it will hop through relays to the '
      'rescue node, whose ACK returns the same way.',
    );
  }

  /// Simulate creation of a fresh SOS (persisted locally through the real
  /// [SosService], then transmitted through the mesh).
  Future<SosRequest> simulateNewSos() async {
    await startMesh();
    return sosService.createSos(
      userId: DemoData.demoUserId,
      people: const PeopleInfo(
        totalPeople: 6,
        childrenCount: 2,
        elderlyCount: 1,
        pregnantWomenCount: 1,
        specialAssistanceCount: 0,
      ),
      emergencyType: EmergencyType.rescueRequired,
      description: 'Demo: water rising near the market complex, people are '
          'stuck on the rooftop. Testing the relay chain.',
      latitude: 17.7400,
      longitude: 83.3150,
      accuracy: 14.0,
    );
  }

  /// Simulate an SOS from another device arriving at this node via relay.
  Future<SosRequest> simulateIncomingFromAnotherDevice() async {
    await startMesh();
    final sosId = idGenerator.sosId(at: _now());
    final origin = 'DEVICE-EXT0001';
    final at = _now().toUtc();
    final priority = sosService.priorityOf(
      emergencyType: EmergencyType.evacuationRequired,
      people: const PeopleInfo(
        totalPeople: 5,
        childrenCount: 1,
        elderlyCount: 1,
        pregnantWomenCount: 0,
        specialAssistanceCount: 1,
      ),
      description: 'External: evacuation needed after sudden flooding.',
    );
    final request = DemoData.externalSos(
      sosId: sosId,
      originDeviceId: origin,
      at: at,
      priority: priority,
    );
    await sosRepository.save(request);

    final packet = SosPacketMessage(
      packetId: idGenerator.packetId(),
      sosId: sosId,
      originDeviceId: origin,
      senderDeviceId: _relayBId,
      hopCount: 1,
      ttl: BleConstants.defaultTtl - 1,
      timestamp: at,
      latitude: request.latitude,
      longitude: request.longitude,
      accuracy: request.accuracy,
      totalPeople: request.people.totalPeople,
      childrenCount: request.people.childrenCount,
      elderlyCount: request.people.elderlyCount,
      pregnantWomenCount: request.people.pregnantWomenCount,
      specialAssistanceCount: request.people.specialAssistanceCount,
      emergencyType: request.emergencyType,
      description: request.description,
      priority: request.priority,
    );
    await mesh.inject(mainDeviceId, codec.encode(packet), _relayBId);
    _log('Incoming SOS packet injected as if relayed by $_relayBId.');
    return request;
  }

  /// Simulate a rescue team acknowledging an SOS (as if the ACK arrived from
  /// the rescue node through the relays).
  Future<void> simulateAckFromRescue(String? sosId) async {
    await startMesh();
    final all = await sosRepository.getAll();
    final target = sosId ?? (all.isNotEmpty ? all.first.sosId : null);
    if (target == null) {
      _log('No SOS available to acknowledge. Create one first.');
      return;
    }
    final request = await sosRepository.getById(target);
    if (request == null) return;

    final ack = AckPacketMessage(
      packetId: idGenerator.ackId(target),
      sosId: target,
      originDeviceId: _rescueId,
      senderDeviceId: _relayBId,
      hopCount: 2,
      ttl: BleConstants.defaultTtl - 2,
      timestamp: _now().toUtc(),
      latitude: request.latitude,
      longitude: request.longitude,
      accuracy: request.accuracy,
    );
    await mesh.inject(mainDeviceId, codec.encode(ack), _relayBId);
    _log('ACK for $target injected as if routed back from $_rescueId.');
  }

  /// Use the status machine to assign a demo team.
  Future<void> assignTeam(String sosId, String teamId) async {
    await sosService.assignTeam(sosId, teamId, actorId: 'RESCUE-DEMO');
    _log('Team $teamId assigned to $sosId.');
  }

  Future<void> startRescue(String sosId) async {
    await sosService.startRescue(sosId, actorId: 'RESCUE-DEMO');
    _log('Rescue started for $sosId.');
  }

  Future<void> resolveSos(String sosId) async {
    await sosService.markResolved(sosId, actorId: 'RESCUE-DEMO');
    _log('$sosId resolved.');
  }

  void _log(String message) {
    if (_events.isClosed) return;
    _events.add(DemoLogEntry(message: message, at: _now()));
  }

  /// Releases every simulated node.
  ///
  /// The three relay transports each own a subscription to the shared
  /// [SimulatedMesh]; leaving them alive keeps the mesh's stream controller
  /// open, which in a test process keeps timers alive and makes `pumpAndSettle`
  /// hang. Disposing them here is what lets a demo-backed test finish.
  Future<void> dispose() async {
    await _queueB.dispose();
    await _queueC.dispose();
    await _queueRescue.dispose();
    await _routerB.dispose();
    await _routerC.dispose();
    await _routerRescue.dispose();
    await _relayB.dispose();
    await _relayC.dispose();
    await _rescueNode.dispose();
    await _events.close();
  }
}