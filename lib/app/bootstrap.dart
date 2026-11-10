/// Bootstrap: wires the whole application.
///
/// Owns construction of Hive storage, the device identity, every repository,
/// every service, the BLE stack (real or simulated), demo machinery and final
/// Riverpod overrides. Tests call [Bootstrap.run] with a temp directory and
/// their own fakes; production calls it with the default options.
///
/// Networking is deliberately NOT started here: the OS permission prompts are
/// only ever triggered from explicit user actions (sending an SOS or enabling
/// the link).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/demo/demo_data.dart';
import '../core/security/device_identity.dart';
import '../core/security/secure_storage.dart';
import '../core/utils/id_generator.dart';
import '../repositories/alert_repository.dart';
import '../repositories/emergency_contact_repository.dart';
import '../repositories/flood_report_repository.dart';
import '../repositories/help_request_repository.dart';
import '../repositories/packet_repository.dart';
import '../repositories/rescue_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/shelter_repository.dart';
import '../repositories/sos_repository.dart';
import '../repositories/user_repository.dart';
import '../services/ble/acknowledgement_service.dart';
import '../services/ble/ble_service.dart';
import '../services/ble/ble_transport.dart';
import '../services/ble/packet_codec.dart';
import '../services/ble/packet_router.dart';
import '../services/ble/real_ble_transport.dart';
import '../services/ble/simulated_ble_transport.dart';
import '../services/ble/transmission_queue.dart';
import '../services/demo/demo_controller.dart';
import '../services/location_service.dart';
import '../services/priority_service.dart';
import '../services/remote/remote_sync.dart';
import '../services/sos_service.dart';
import '../services/speech_service.dart';
import 'providers.dart';

/// Upper bound on how long starting the peer-to-peer link may take.
///
/// Long enough for a real permission dialog plus a scan on slow hardware,
/// short enough that a stuck transport cannot hold the app before `runApp`.
const Duration startLinkTimeout = Duration(seconds: 20);

class BootstrapOptions {
  const BootstrapOptions({
    this.boxPath,
    this.demoModeOverride,
    this.seedDemoData = true,
    this.autoStartNetworking = false,
    this.useSimulatedTransport = true,
    this.locationService,
    this.speechService,
    this.now,
    this.userRepository,
    this.sosRepository,
    this.settingsRepository,
    this.packetRepository,
    this.rescueRepository,
  });

  /// When set, Hive is initialised against this directory. Production uses
  /// Hive.initFlutter(); tests point at a temporary folder.
  final String? boxPath;

  /// Forces demo mode on/off. When null it defaults to [seedDemoData].
  final bool? demoModeOverride;

  /// Whether demo teams and seed SOSs are inserted on bootstrap.
  final bool seedDemoData;

  /// Whether the link starts automatically after wiring. Defaults to false —
  /// the UI starts networking from explicit user actions.
  final bool autoStartNetworking;

  /// true = in-process simulated mesh (default, used for demo and tests);
  /// false = real BLE hardware link.
  final bool useSimulatedTransport;

  final LocationService? locationService;
  final SpeechService? speechService;
  final DateTime Function()? now;

  /// Optional repository injections.
  ///
  /// Production leaves these null and gets the Hive-backed implementations.
  /// Tests inject synchronous in-memory repositories so that a widget test
  /// never blocks on Hive file I/O inside Flutter's fake-async zone.
  final UserRepository? userRepository;
  final SosRepository? sosRepository;
  final SettingsRepository? settingsRepository;
  final PacketRepository? packetRepository;
  final RescueRepository? rescueRepository;
}

class BootstrapResult {
  const BootstrapResult({
    required this.wrapWithProviders,
    required this.deviceId,
    required this.demoController,
    required this.startNetworking,
    required this.stopNetworking,
    required this.dispose,
  });

  /// Wraps a widget subtree in a Riverpod [ProviderScope] carrying every
  /// override this bootstrap produced. The root [WidgetsFlutterBinding]
  /// material is applied by the caller (e.g. `bootstrap.wrapWithProviders(
  /// WidgetsApp(...))`).
  final Widget Function(Widget child) wrapWithProviders;
  /// The stable device identity used for this install.
  final String deviceId;

  /// Present only when the simulated demo mesh is available.
  final DemoController? demoController;

  /// Starts shared networking: the demo mesh (when present) plus the BLE
  /// link. [requestPermissions] must only be true from a user action.
  final Future<void> Function({bool requestPermissions}) startNetworking;

  final Future<void> Function() stopNetworking;

  /// Closes streams, disposes transports and closes Hive.
  final Future<void> Function() dispose;
}

class Bootstrap {
  Bootstrap._();

  /// Wires every dependency and resolves the Riverpod override list.
  static Future<BootstrapResult> run(BootstrapOptions options) async {
    final now = options.now ?? _defaultNow;
    final idGenerator = IdGenerator();

    // -----------------------------------------------------------------------
    // Hive storage
    // -----------------------------------------------------------------------
    final boxPath = options.boxPath;
    if (boxPath != null) {
      Hive.init(boxPath);
    } else {
      await Hive.initFlutter();
    }

    // Platform-aware key storage:
    //  * VM (Android, production): the AES key lives in a file inside the app
    //    documents directory (`FileEncryptionKeyStore`) and the device box is
    //    encrypted at rest.
    //  * Tests (`boxPath` set) and web: no filesystem/platform channels are
    //    available (path_provider has no web implementation and `dart:io`
    //    files do not exist there), so the key store is in-memory and boxes
    //    are opened plain. Hive still persists boxes — on web through
    //    IndexedDB (its JS backend), so no functionality is lost beyond
    //    at-rest encryption of the device box.
    final usePlainBoxes = boxPath != null || kIsWeb;
    final keyManager = SecureKeyManager(
      usePlainBoxes
          ? InMemoryEncryptionKeyStore()
          : await FileEncryptionKeyStore.create(),
    );
    final fallbackToPlain = usePlainBoxes;

    final deviceBox = await openEncryptedBox(
      Boxes.device,
      keyManager: keyManager,
      fallbackToPlain: fallbackToPlain,
    );
    final userBox = await Hive.openBox(Boxes.user);
    final sosBox = await Hive.openBox(Boxes.sos);
    final packetsBox = await Hive.openBox(Boxes.packets);
    final outboxBox = await Hive.openBox(Boxes.outbox);
    final dupBox = await Hive.openBox(Boxes.dupCache);
    final teamsBox = await Hive.openBox(Boxes.teams);
    final settingsBox = await Hive.openBox(Boxes.settings);
    final floodReportsBox = await Hive.openBox(Boxes.floodReports);
    final helpRequestsBox = await Hive.openBox(Boxes.helpRequests);
    final sheltersBox = await Hive.openBox(Boxes.shelters);
    final contactsBox = await Hive.openBox(Boxes.contacts);
    final alertsBox = await Hive.openBox(Boxes.alerts);

    // -----------------------------------------------------------------------
    // Identity + repositories
    // -----------------------------------------------------------------------
    final identityService =
        DeviceIdentityService(deviceBox, idGenerator);
    final identity = identityService.getOrCreate();
    final deviceId = identity.deviceId;

    final userRepository =
        options.userRepository ?? HiveUserRepository(userBox);
    final sosRepository = options.sosRepository ?? HiveSosRepository(sosBox);
    final packetRepository =
        options.packetRepository ??
            HivePacketRepository(packetsBox, outboxBox, dupBox);
    final rescueRepository =
        options.rescueRepository ?? HiveRescueRepository(teamsBox);
    final settingsRepository =
        options.settingsRepository ?? HiveSettingsRepository(settingsBox);
    final floodReportRepository = HiveFloodReportRepository(floodReportsBox);
    final helpRequestRepository = HiveHelpRequestRepository(helpRequestsBox);
    final shelterRepository = HiveShelterRepository(sheltersBox);
    final alertRepository = HiveAlertRepository(alertsBox);
    final emergencyContactRepository =
        HiveEmergencyContactRepository(contactsBox);

    // -----------------------------------------------------------------------
    // Services
    // -----------------------------------------------------------------------
    const codec = PacketCodec();
    const priorityService = PriorityService(PriorityConfig());
    final locationService =
        options.locationService ?? const GeolocatorLocationService();
    final speechService =
        options.speechService ?? const UnavailableSpeechService();
    final remoteSync = DisabledRemoteSyncService();

    final demoMode = options.demoModeOverride ?? options.seedDemoData;
    await settingsRepository.setBool(SettingsKeys.demoMode, demoMode);

    // -----------------------------------------------------------------------
    // BLE stack on the main transport
    // -----------------------------------------------------------------------
    final mesh = SimulatedMesh();
    final BleTransport transport;
    if (options.useSimulatedTransport) {
      transport = SimulatedBleTransport(mesh: mesh, localDeviceId: deviceId);
    } else {
      transport = RealBleTransport(localDeviceId: deviceId);
    }

    final queue = TransmissionQueue(
      packetRepository: packetRepository,
      transport: transport,
      codec: codec,
      now: now,
    );

    SosService? sosService;
    final ackService = AcknowledgementService(
      localDeviceId: deviceId,
      idGenerator: idGenerator,
      autoAck: false,
      ownsSos: (sosId) => sosService?.ownsSos(sosId) ?? Future.value(false),
      onAckReceived: (sosId) async {
        await sosService?.acknowledgeSos(sosId,
            teamId: 'RESCUE-NODE');
      },
      now: now,
    );

    sosService = SosService(
      sosRepository: sosRepository,
      packetRepository: packetRepository,
      priorityService: priorityService,
      idGenerator: idGenerator,
      queue: queue,
      originDeviceId: deviceId,
      now: now,
    );

    final router = PacketRouter(
      packetRepository: packetRepository,
      codec: codec,
      transport: transport,
      queue: queue,
      nodeDeviceId: deviceId,
      now: now,
    )..ackService = ackService;
    ackService.attachRouter(router);

    final bleService = BleService(
      transport: transport,
      router: router,
      queue: queue,
      ackService: ackService,
      idGenerator: idGenerator,
      localDeviceId: deviceId,
    );

    transport.incoming.listen((packet) {
      unawaited(router.routeIncoming(packet.payload));
    });

    // -----------------------------------------------------------------------
    // Seed data
    // -----------------------------------------------------------------------
    if (options.seedDemoData) {
      for (final team in DemoData.rescueTeams()) {
        await rescueRepository.saveTeam(team);
      }
      if (demoMode) {
        final seeds = DemoData.seedSos(
          now: now,
          originDeviceId: deviceId,
          priorityOf:
              ({required emergencyType, required people, required description}) =>
                  priorityService
                      .evaluate(
                        emergencyType: emergencyType,
                        people: people,
                        description: description,
                      )
                      .priority,
        );
        for (final seed in seeds) {
          await sosRepository.save(seed);
        }
      }
    }

    // -----------------------------------------------------------------------
    // Demo machinery (simulated mesh only)
    // -----------------------------------------------------------------------
    DemoController? demoController;
    if (options.useSimulatedTransport && demoMode) {
      demoController = DemoController(
        sosService: sosService,
        sosRepository: sosRepository,
        mesh: mesh,
        mainTransport: transport,
        mainRouter: router,
        mainDeviceId: deviceId,
        idGenerator: idGenerator,
        codec: codec,
        now: now,
      );
    }

    // -----------------------------------------------------------------------
    // Networking entry points
    // -----------------------------------------------------------------------
    //
    // `startNetworking` is bounded by [startLinkTimeout]. A BLE stack that
    // never completes its scan (a known behaviour when the radio is off, and
    // on some emulator images) would otherwise block forever: during bootstrap
    // that means `main` never reaches `runApp` — a white screen with no way to
    // report it — and from a button it means an unkillable loading state.
    Future<void> startNetworking({bool requestPermissions = false}) async {
      try {
        await Future.wait([
          if (demoController != null) demoController.startMesh(),
          bleService.startLink(requestPermissions: requestPermissions),
        ]).timeout(
          startLinkTimeout,
          onTimeout: () => throw TimeoutException(
            'The peer-to-peer link did not start within '
            '${startLinkTimeout.inSeconds}s.',
            startLinkTimeout,
          ),
        );
      } on TimeoutException catch (e) {
        // Deliberately swallowed: the transport's own state stream already
        // reports the failure to the UI, and a throw here would blank the
        // screen that asked for the link.
        debugPrint('FloodRelief: ${e.message}');
      }
    }

    Future<void> stopNetworking() async {
      await bleService.stop();
    }

    Future<void> dispose() async {
      await demoController?.dispose();
      await bleService.dispose();
      await queue.dispose();
      await router.dispose();
      await transport.dispose();
      await Hive.close();
    }

    // -----------------------------------------------------------------------
    // Provider wiring
    // -----------------------------------------------------------------------
    // Riverpod 3 does not expose the `Override` type publicly, so the override
    // list is kept as an inline literal inside this closure rather than naming
    // the type anywhere.
    Widget wrapWithProviders(Widget child) {
      return ProviderScope(
        overrides: [
          deviceIdentityProvider.overrideWithValue(identityService),
          userRepositoryProvider.overrideWithValue(userRepository),
          sosRepositoryProvider.overrideWithValue(sosRepository),
          packetRepositoryProvider.overrideWithValue(packetRepository),
          rescueRepositoryProvider.overrideWithValue(rescueRepository),
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          floodReportRepositoryProvider.overrideWithValue(floodReportRepository),
          helpRequestRepositoryProvider.overrideWithValue(helpRequestRepository),
          shelterRepositoryProvider.overrideWithValue(shelterRepository),
          alertRepositoryProvider.overrideWithValue(alertRepository),
          emergencyContactRepositoryProvider
              .overrideWithValue(emergencyContactRepository),
          locationServiceProvider.overrideWithValue(locationService),
          transportProvider.overrideWithValue(transport),
          simulatedMeshProvider.overrideWithValue(mesh),
          remoteSyncServiceProvider.overrideWithValue(remoteSync),
          idGeneratorProvider.overrideWithValue(idGenerator),
          priorityServiceProvider.overrideWithValue(priorityService),
          speechServiceProvider.overrideWithValue(speechService),
          transmissionQueueProvider.overrideWithValue(queue),
          sosServiceProvider.overrideWithValue(sosService!),
          acknowledgementServiceProvider.overrideWithValue(ackService),
          packetRouterProvider.overrideWithValue(router),
          bleServiceProvider.overrideWithValue(bleService),
          networkingProvider.overrideWithValue(
            NetworkingHandle(start: startNetworking, stop: stopNetworking),
          ),
          if (demoController != null)
            demoControllerProvider.overrideWithValue(demoController),
        ],
        child: child,
      );
    }

    if (options.autoStartNetworking) {
      await startNetworking();
    }

    return BootstrapResult(
      wrapWithProviders: wrapWithProviders,
      deviceId: deviceId,
      demoController: demoController,
      startNetworking: startNetworking,
      stopNetworking: stopNetworking,
      dispose: dispose,
    );
  }

  static DateTime _defaultNow() => DateTime.now().toUtc();
}