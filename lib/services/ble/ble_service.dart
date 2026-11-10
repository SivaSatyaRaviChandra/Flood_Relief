/// Top-level BLE orchestrator: wires transport + router + queue + ACK and
/// exposes a single status stream for the UI.
library;

import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/utils/id_generator.dart';
import '../../models/sos_request.dart';
import '../../models/sos_packet.dart';
import '../ble/acknowledgement_service.dart';
import '../ble/ble_transport.dart';
import '../ble/packet_router.dart';
import '../ble/transmission_queue.dart';

enum CommunicationState {
  idle,
  starting,
  relaySearching,
  attempting,
  ackReceived,
  stopped,
  error,
}

class CommunicationStatus {
  const CommunicationStatus(this.state, this.detail);

  final CommunicationState state;
  final String detail;
}

class BleService {
  BleService({
    required this.transport,
    required this.router,
    required this.queue,
    required this.ackService,
    required this.idGenerator,
    required this.localDeviceId,
  });

  final BleTransport transport;
  final PacketRouter router;
  final TransmissionQueue queue;
  final AcknowledgementService ackService;
  final IdGenerator idGenerator;
  final String localDeviceId;

  final _status = StreamController<CommunicationStatus>.broadcast();
  Stream<CommunicationStatus> get status => _status.stream;

  final Set<StreamSubscription> _subscriptions = {};
  bool _started = false;

  Future<void> start() => startLink(requestPermissions: false);

  /// Start the peer-to-peer link. Permissions are requested only when
  /// [requestPermissions] is true, which callers must only do from explicit
  /// user actions (sending an SOS, enabling the link). Cold-start networking
  /// never triggers OS permission prompts.
  Future<void> startLink({bool requestPermissions = false}) async {
    if (_started) return;
    _started = true;

    _subscriptions.add(transport.state.listen((state) {
      switch (state) {
        case BleTransportState.idle:
          _publish(CommunicationState.idle, 'Link idle.');
        case BleTransportState.starting:
          _publish(
            CommunicationState.starting,
            'Starting peer-to-peer link...',
          );
        case BleTransportState.advertising:
        case BleTransportState.scanning:
          _publish(
            CommunicationState.relaySearching,
            'Searching for a nearby relay/rescue device...',
          );
        case BleTransportState.connected:
          _publish(
            CommunicationState.attempting,
            'Linked to a nearby device; transmitting queued SOS packets...',
          );
          // The link has peers again: retry every packet still pending so
          // nothing saved-but-undelivered is left behind.
          unawaited(queue.retryPending());
        case BleTransportState.error:
          _publish(
            CommunicationState.error,
            'The peer-to-peer link is unavailable on this device.',
          );
      }
    }));

    _subscriptions.add(queue.events.listen((event) {
      switch (event.kind) {
        case QueueEventKind.enqueued:
          _publish(
            CommunicationState.relaySearching,
            'SOS saved. Searching for a nearby relay/rescue device...',
          );
        case QueueEventKind.broadcast:
        case QueueEventKind.retrying:
          _publish(
            CommunicationState.attempting,
            'Attempting to reach relay/rescue devices...',
          );
        case QueueEventKind.ackReceived:
          _publish(
            CommunicationState.ackReceived,
            'Your SOS has been received by rescue.',
          );
        case QueueEventKind.timeout:
        case QueueEventKind.gaveUpAttempts:
          _publish(
            CommunicationState.relaySearching,
            'Still searching. Your SOS remains saved on this device and will '
            'be transmitted when a peer is reachable.',
          );
      }
    }));

    try {
      await transport.start(requestPermissions: requestPermissions);
    } catch (_) {
      _publish(
        CommunicationState.error,
        'Could not start the peer-to-peer link.',
      );
    }
  }

  /// Compose and queue an SOS packet for an existing [request].
  Future<void> sendSos(SosRequest request) async {
    final packet = SosPacketMessage(
      packetId: idGenerator.packetId(),
      sosId: request.sosId,
      originDeviceId: request.originDeviceId,
      senderDeviceId: localDeviceId,
      hopCount: 0,
      ttl: BleConstants.defaultTtl,
      timestamp: DateTime.now().toUtc(),
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
    await router.routeOutgoing(packet);
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await transport.stop();
    _started = false;
    _publish(CommunicationState.stopped, 'Peer-to-peer link stopped.');
  }

  Future<void> dispose() async {
    await stop();
    await _status.close();
  }

  void _publish(CommunicationState state, String detail) {
    if (_status.isClosed) return;
    _status.add(CommunicationStatus(state, detail));
  }
}