/// Application providers.
///
/// Concrete dependencies are wired by `bootstrap.dart` (or tests) through
/// `ProviderScope` overrides. Widgets and notifiers only depend on these
/// interfaces — the UI never touches the database or a radio directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/security/device_identity.dart';
import '../core/utils/id_generator.dart';
import '../models/alert_record.dart';
import '../models/app_user.dart';
import '../models/emergency_contact.dart';
import '../models/enums/alert_severity.dart';
import '../models/enums/flood_severity.dart';
import '../models/flood_report.dart';
import '../models/help_request.dart';
import '../models/rescue_team.dart';
import '../models/shelter.dart';
import '../models/sos_request.dart';
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
import '../services/alert_service.dart';
import '../services/ble/acknowledgement_service.dart';
import '../services/ble/ble_service.dart';
import '../services/ble/ble_transport.dart';
import '../services/ble/packet_codec.dart';
import '../services/ble/packet_router.dart';
import '../services/ble/simulated_ble_transport.dart';
import '../services/ble/transmission_queue.dart';
import '../services/demo/demo_controller.dart';
import '../services/emergency_contact_service.dart';
import '../services/flood_report_service.dart';
import '../services/help_request_service.dart';
import '../services/local_data_service.dart';
import '../services/location_service.dart';
import '../services/priority_service.dart';
import '../services/remote/remote_sync.dart';
import '../services/rescue_team_service.dart';
import '../services/shelter_service.dart';
import '../services/sos_service.dart';
import '../services/speech_service.dart';
import 'error_surface.dart';

// ---------------------------------------------------------------------------
// Wired by bootstrap (tests may override any of these).
// ---------------------------------------------------------------------------

final deviceIdentityProvider = Provider<DeviceIdentityService>(
  (ref) => throw UnimplementedError('bootstrap did not wire device identity'),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire user repository'),
);

final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire SOS repository'),
);

final packetRepositoryProvider = Provider<PacketRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire packet repository'),
);

final rescueRepositoryProvider = Provider<RescueRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire rescue repository'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire settings repository'),
);

final floodReportRepositoryProvider = Provider<FloodReportRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire flood report repository'),
);

final helpRequestRepositoryProvider = Provider<HelpRequestRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire help request repository'),
);

final shelterRepositoryProvider = Provider<ShelterRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire shelter repository'),
);

final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => throw UnimplementedError('bootstrap did not wire alert repository'),
);

final emergencyContactRepositoryProvider = Provider<EmergencyContactRepository>(
  (ref) => throw UnimplementedError(
    'bootstrap did not wire emergency contact repository',
  ),
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => throw UnimplementedError('bootstrap did not wire location service'),
);

final transportProvider = Provider<BleTransport>(
  (ref) => throw UnimplementedError('bootstrap did not wire BLE transport'),
);

final simulatedMeshProvider = Provider<SimulatedMesh?>((ref) => null);

final remoteSyncServiceProvider =
    Provider<RemoteSyncService>((ref) => DisabledRemoteSyncService());

final idGeneratorProvider = Provider<IdGenerator>((ref) => IdGenerator());

// ---------------------------------------------------------------------------
// Composable services (pure by default; deterministic in tests).
// ---------------------------------------------------------------------------

final packetCodecProvider =
    Provider<PacketCodec>((ref) => const PacketCodec());

final priorityServiceProvider =
    Provider<PriorityService>((ref) => const PriorityService(PriorityConfig()));

final speechServiceProvider =
    Provider<SpeechService>((ref) => const UnavailableSpeechService());

final transmissionQueueProvider = Provider<TransmissionQueue>((ref) {
  return TransmissionQueue(
    packetRepository: ref.watch(packetRepositoryProvider),
    transport: ref.watch(transportProvider),
    codec: ref.watch(packetCodecProvider),
  );
});

final sosServiceProvider = Provider<SosService>((ref) {
  throw UnimplementedError('bootstrap did not wire SOS service');
});

final acknowledgementServiceProvider = Provider<AcknowledgementService>((ref) {
  throw UnimplementedError('bootstrap did not wire ACK service');
});

final packetRouterProvider = Provider<PacketRouter>((ref) {
  throw UnimplementedError('bootstrap did not wire packet router');
});

final bleServiceProvider = Provider<BleService>((ref) {
  throw UnimplementedError('bootstrap did not wire BLE service');
});

// ---------------------------------------------------------------------------
// Field-reporting services.
//
// These are pure compositions of a repository plus the id generator, so they
// are built here rather than in `bootstrap.dart`; bootstrap only overrides the
// *repositories*. Tests therefore only need to substitute storage.
// ---------------------------------------------------------------------------

final floodReportServiceProvider = Provider<FloodReportService>(
  (ref) => FloodReportService(
    repository: ref.watch(floodReportRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final helpRequestServiceProvider = Provider<HelpRequestService>(
  (ref) => HelpRequestService(
    repository: ref.watch(helpRequestRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final shelterServiceProvider = Provider<ShelterService>(
  (ref) => ShelterService(
    repository: ref.watch(shelterRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final emergencyContactServiceProvider = Provider<EmergencyContactService>(
  (ref) => EmergencyContactService(
    repository: ref.watch(emergencyContactRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final rescueTeamServiceProvider = Provider<RescueTeamService>(
  (ref) => RescueTeamService(
    repository: ref.watch(rescueRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final alertServiceProvider = Provider<AlertService>(
  (ref) => AlertService(
    alertRepository: ref.watch(alertRepositoryProvider),
    sosRepository: ref.watch(sosRepositoryProvider),
    floodReportRepository: ref.watch(floodReportRepositoryProvider),
    helpRequestRepository: ref.watch(helpRequestRepositoryProvider),
    shelterRepository: ref.watch(shelterRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final localDataServiceProvider = Provider<LocalDataService>(
  (ref) => LocalDataService(
    sosRepository: ref.watch(sosRepositoryProvider),
    packetRepository: ref.watch(packetRepositoryProvider),
    floodReportRepository: ref.watch(floodReportRepositoryProvider),
    helpRequestRepository: ref.watch(helpRequestRepositoryProvider),
    alertRepository: ref.watch(alertRepositoryProvider),
    contactRepository: ref.watch(emergencyContactRepositoryProvider),
    shelterRepository: ref.watch(shelterRepositoryProvider),
  ),
);

/// The bounded framework-error log surfaced in Settings → Diagnostics.
final errorLogProvider = Provider<ErrorLog>((ref) => errorLog);

final demoControllerProvider = Provider<DemoController?>((ref) => null);

/// Handle for explicitly starting/stopping the shared link from user actions
/// (permissions are only requested from such actions, never cold start).
class NetworkingHandle {
  const NetworkingHandle({required this.start, required this.stop});

  final Future<void> Function({bool requestPermissions}) start;
  final Future<void> Function() stop;
}

final networkingProvider = Provider<NetworkingHandle>(
  (ref) => throw UnimplementedError('bootstrap did not wire networking'),
);

/// The stable device id of this install.
final deviceIdProvider = Provider<String>((ref) {
  return ref.watch(deviceIdentityProvider).getOrCreate().deviceId;
});

// ---------------------------------------------------------------------------
// UI-facing state
// ---------------------------------------------------------------------------

final allSosProvider = StreamProvider<List<SosRequest>>((ref) {
  return ref.watch(sosRepositoryProvider).watchAll();
});

final mySosProvider = Provider<AsyncValue<List<SosRequest>>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final allAsync = ref.watch(allSosProvider);
  return allAsync.whenData((all) {
    final user = userAsync.value;
    if (user == null) return all;
    return all.where((s) => s.userId == user.userId).toList();
  });
});

final sosByIdProvider = Provider.family<AsyncValue<SosRequest?>, String>(
  (ref, sosId) {
    final allAsync = ref.watch(allSosProvider);
    if (allAsync.isLoading) return const AsyncValue.loading();
    if (allAsync.hasError) {
      return AsyncValue<SosRequest?>.error(allAsync.error!, StackTrace.current);
    }
    final all = allAsync.value ?? const <SosRequest>[];
    final found = all.where((s) => s.sosId == sosId);
    return AsyncValue.data(found.isEmpty ? null : found.first);
  },
);

final teamsProvider = StreamProvider<List<RescueTeam>>((ref) {
  return ref.watch(rescueRepositoryProvider).watchTeams();
});

final communicationStatusProvider = StreamProvider((ref) {
  return ref.watch(bleServiceProvider).status;
});

final queueEventsProvider = StreamProvider((ref) {
  return ref.watch(transmissionQueueProvider).events;
});

final routingEventsProvider = StreamProvider((ref) {
  return ref.watch(packetRouterProvider).events;
});

final demoLogProvider = StreamProvider((ref) {
  final controller = ref.watch(demoControllerProvider);
  if (controller == null) return const Stream.empty();
  return controller.events;
});

// ---------------------------------------------------------------------------
// Field-reporting streams
// ---------------------------------------------------------------------------

final floodReportsProvider = StreamProvider<List<FloodReport>>((ref) {
  return ref.watch(floodReportRepositoryProvider).watchAll();
});

final helpRequestsProvider = StreamProvider<List<HelpRequest>>((ref) {
  return ref.watch(helpRequestRepositoryProvider).watchAll();
});

final sheltersProvider = StreamProvider<List<Shelter>>((ref) {
  return ref.watch(shelterRepositoryProvider).watchAll();
});

final contactsProvider = StreamProvider<List<EmergencyContact>>((ref) {
  return ref.watch(emergencyContactRepositoryProvider).watchAll();
});

final alertsProvider = StreamProvider<List<AlertRecord>>((ref) {
  return ref.watch(alertRepositoryProvider).watchAll();
});

/// Flood reports filed by the signed-in user, newest first.
final myFloodReportsProvider = Provider<AsyncValue<List<FloodReport>>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return ref.watch(floodReportsProvider).whenData((all) {
    if (user == null) return all;
    return all.where((r) => r.reporterId == user.userId).toList();
  });
});

/// Help requests filed by the signed-in user, newest first.
final myHelpRequestsProvider = Provider<AsyncValue<List<HelpRequest>>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return ref.watch(helpRequestsProvider).whenData((all) {
    if (user == null) return all;
    return all.where((r) => r.reporterId == user.userId).toList();
  });
});

// ---------------------------------------------------------------------------
// Derived dashboard state
// ---------------------------------------------------------------------------

/// The last position the app managed to capture, or null when none was.
final lastKnownPositionProvider = Provider<({double lat, double lng})?>((ref) {
  final result = ref.watch(locationStateProvider).result;
  if (result is! LocationSuccess) return null;
  return (lat: result.latitude, lng: result.longitude);
});

/// Shelters sorted by distance from the last known position.
///
/// Shelters without coordinates sort last rather than being dropped, so a
/// shelter added by hand is never invisible.
final nearbySheltersProvider =
    FutureProvider<List<({Shelter shelter, double? distanceMetres})>>((ref) {
  final position = ref.watch(lastKnownPositionProvider);
  return ref.watch(shelterServiceProvider).nearby(
        latitude: position?.lat,
        longitude: position?.lng,
      );
});

/// How many alerts are unread. Cheap: the repository counts in memory.
final unreadAlertsProvider = FutureProvider<int>((ref) {
  return ref.watch(alertRepositoryProvider).unreadCount();
});

/// Packets still queued for transmission. This is the real outbox state, not
/// an estimate — it is read from the same repository the queue writes to.
final pendingPacketCountProvider = FutureProvider<int>((ref) async {
  // `watchPending` fires on every outbox write, so the count stays live.
  final pending = await ref.watch(packetRepositoryProvider).pendingPacketIds();
  ref.watch(packetRepositoryProvider).watchPending();
  return pending.length;
});

/// Everything the dashboard's "situation" panel shows, computed from local
/// data only. Nothing here is estimated or fetched.
class SituationSummary {
  const SituationSummary({
    required this.activeSos,
    required this.openHelpRequests,
    required this.freshFloodReports,
    required this.peopleInFloodReports,
    required this.peakFloodSeverity,
    required this.sheltersWithSpace,
    required this.sheltersTotal,
    required this.unreadAlerts,
  });

  final int activeSos;
  final int openHelpRequests;
  final int freshFloodReports;
  final int peopleInFloodReports;
  final FloodSeverity? peakFloodSeverity;
  final int sheltersWithSpace;
  final int sheltersTotal;
  final int unreadAlerts;

  bool get isQuiet =>
      activeSos == 0 &&
      openHelpRequests == 0 &&
      freshFloodReports == 0 &&
      unreadAlerts == 0;

  /// One honest sentence for the dashboard header.
  String get headline {
    if (isQuiet) return 'Nothing urgent recorded on this device.';
    final parts = <String>[];
    if (activeSos > 0) {
      parts.add('$activeSos active SOS${activeSos == 1 ? '' : 's'}');
    }
    if (openHelpRequests > 0) {
      parts.add(
        '$openHelpRequests open help request${openHelpRequests == 1 ? '' : 's'}',
      );
    }
    if (freshFloodReports > 0) {
      parts.add(
        '$freshFloodReports flood report${freshFloodReports == 1 ? '' : 's'}',
      );
    }
    if (unreadAlerts > 0) {
      parts.add('$unreadAlerts unread alert${unreadAlerts == 1 ? '' : 's'}');
    }
    return '${parts.join(', ')} on this device.';
  }
}

final situationSummaryProvider = Provider<SituationSummary?>((ref) {
  final sos = ref.watch(allSosProvider);
  final requests = ref.watch(helpRequestsProvider);
  final reports = ref.watch(floodReportsProvider);
  final shelters = ref.watch(sheltersProvider);
  final unread = ref.watch(unreadAlertsProvider);

  if (!sos.hasValue ||
      !requests.hasValue ||
      !reports.hasValue ||
      !shelters.hasValue ||
      !unread.hasValue) {
    return null;
  }

  final now = DateTime.now().toUtc();
  final cutoff = now.subtract(Limits.floodReportFreshness);
  final fresh =
      reports.value!.where((r) => !r.timestamp.isBefore(cutoff)).toList();
  final allShelters = shelters.value!;

  return SituationSummary(
    activeSos: sos.value!.where((s) => s.status.isActive).length,
    openHelpRequests: requests.value!.where((r) => r.isOpen).length,
    freshFloodReports: fresh.length,
    peopleInFloodReports:
        fresh.fold<int>(0, (sum, r) => sum + r.affectedPeople),
    peakFloodSeverity: _peakSeverity(fresh),
    sheltersWithSpace: allShelters
        .where((s) => s.open && s.availableCapacity > 0)
        .length,
    sheltersTotal: allShelters.length,
    unreadAlerts: unread.value!,
  );
});

FloodSeverity? _peakSeverity(List<FloodReport> reports) {
  FloodSeverity? peak;
  for (final report in reports) {
    if (peak == null || report.severity.weight > peak.weight) {
      peak = report.severity;
    }
  }
  return peak;
}

/// Highest alert severity currently unread, used to colour the dashboard
/// banner.
final topAlertSeverityProvider = Provider<AlertSeverity?>((ref) {
  final alerts = ref.watch(alertsProvider).value;
  if (alerts == null) return null;
  AlertSeverity? top;
  for (final alert in alerts) {
    if (alert.read) continue;
    if (top == null || alert.severity.weight > top.weight) top = alert.severity;
  }
  return top;
});

// ---------------------------------------------------------------------------
// Notifiers
// ---------------------------------------------------------------------------

class CurrentUserNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    return ref.watch(userRepositoryProvider).currentUser();
  }

  Future<void> signIn(AppUser user) async {
    await ref.read(userRepositoryProvider).saveUser(user);
    state = AsyncValue.data(user);
  }

  Future<void> signOut() async {
    await ref.read(userRepositoryProvider).clear();
    state = const AsyncValue.data(null);
  }

  /// Persists a change to the signed-in user (currently only the rescue
  /// operator's team selection).
  Future<void> updateUser(AppUser user) async {
    await ref.read(userRepositoryProvider).saveUser(user);
    state = AsyncValue.data(user);
  }
}

final currentUserProvider =
    AsyncNotifierProvider<CurrentUserNotifier, AppUser?>(CurrentUserNotifier.new);

class DemoModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref
        .watch(settingsRepositoryProvider)
        .getBool(SettingsKeys.demoMode, fallback: true);
  }

  Future<void> setEnabled(bool enabled) async {
    await ref.read(settingsRepositoryProvider).setBool(SettingsKeys.demoMode, enabled);
    state = AsyncValue.data(enabled);
  }
}

final demoModeProvider =
    AsyncNotifierProvider<DemoModeNotifier, bool>(DemoModeNotifier.new);

/// A persisted on/off setting backed by the settings box.
class SettingToggleNotifier extends AsyncNotifier<bool> {
  SettingToggleNotifier(this.key, {this.fallback = true});

  final String key;
  final bool fallback;

  @override
  Future<bool> build() =>
      ref.watch(settingsRepositoryProvider).getBool(key, fallback: fallback);

  Future<void> set(bool value) async {
    // Optimistic: the switch must not snap back while the write is in flight.
    state = AsyncValue.data(value);
    try {
      await ref.read(settingsRepositoryProvider).setBool(key, value);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

/// Start the peer-to-peer link automatically right after an SOS is saved.
final autoStartLinkAfterSosProvider =
    AsyncNotifierProvider<SettingToggleNotifier, bool>(
  () => SettingToggleNotifier(SettingsKeys.autoStartLinkAfterSos, fallback: true),
);

/// Show the newest alert as a banner on the dashboard.
final showAlertBannerProvider =
    AsyncNotifierProvider<SettingToggleNotifier, bool>(
  () => SettingToggleNotifier(SettingsKeys.showAlertBanner, fallback: true),
);

/// Whether onboarding has been completed at least once. The boot gate uses
/// this only to decide whether to show onboarding before any user exists; a
/// missing value is treated as "not completed".
final onboardingCompleteProvider = AsyncNotifierProvider<SettingToggleNotifier, bool>(
  () => SettingToggleNotifier(SettingsKeys.onboardingComplete, fallback: false),
);

/// Location capture state with a manual retry entry point.
class LocationState {
  const LocationState({this.loading = false, this.result});

  final bool loading;
  final LocationResult? result;

  LocationState copyWith({bool? loading, LocationResult? result}) => LocationState(
        loading: loading ?? this.loading,
        result: result ?? this.result,
      );
}

class LocationNotifier extends Notifier<LocationState> {
  @override
  LocationState build() {
    Future.microtask(reload);
    return const LocationState();
  }

  Future<void> reload() async {
    state = const LocationState(loading: true);
    final result =
        await ref.read(locationServiceProvider).getCurrentLocation();
    state = LocationState(loading: false, result: result);
    // Remember the last good fix so the dashboard can show a position even
    // before a fresh one arrives (and when permission is later revoked).
    if (result is LocationSuccess) {
      final settings = ref.read(settingsRepositoryProvider);
      await settings.setString(SettingsKeys.lastLatitude, '${result.latitude}');
      await settings.setString(
        SettingsKeys.lastLongitude,
        '${result.longitude}',
      );
      if (result.accuracy != null) {
        await settings.setString(
          SettingsKeys.lastAccuracy,
          '${result.accuracy}',
        );
      }
    }
  }
}

final locationStateProvider =
    NotifierProvider<LocationNotifier, LocationState>(LocationNotifier.new);

/// Persisted location permission, polled from the OS on demand.
class LocationPermissionNotifier extends AsyncNotifier<LocationPermissionState> {
  @override
  Future<LocationPermissionState> build() {
    return ref.watch(locationServiceProvider).checkPermission();
  }

  /// Asks the OS for the permission. Returns the resulting state so the caller
  /// can report it without a second round trip.
  Future<LocationPermissionState> request() async {
    final next = await ref.read(locationServiceProvider).requestPermission();
    state = AsyncValue.data(next);
    return next;
  }

  /// Re-reads the current state (e.g. after the user returns from system
  /// settings).
  Future<LocationPermissionState> refresh() async {
    final next = await ref.read(locationServiceProvider).checkPermission();
    state = AsyncValue.data(next);
    return next;
  }
}

final locationPermissionProvider =
    AsyncNotifierProvider<LocationPermissionNotifier, LocationPermissionState>(
  LocationPermissionNotifier.new,
);

/// Opens the OS app-settings page for this app. Returns false when the
/// platform could not open it (e.g. web), so the caller can say so instead of
/// pretending the user was sent somewhere.
final openAppSettingsProvider = Provider<Future<bool> Function()>((ref) {
  return () => ref.read(locationServiceProvider).openAppSettings();
});

/// Re-derives the alert feed whenever the data it is derived from changes.
///
/// [AlertService.refresh] is idempotent (alerts carry a dedupe key), so this
/// can run on every change without duplicating entries. The state is the time
/// of the last successful derivation, shown on the Alerts screen.
class AlertFeedRefresher extends Notifier<DateTime?> {
  /// The last derivation failure, surfaced by the Alerts screen instead of
  /// being swallowed. Null whenever the last attempt succeeded.
  Object? lastFailure;

  @override
  DateTime? build() {
    lastFailure = null;
    // Watching the four source streams is what makes this reactive; the
    // service itself does not subscribe.
    ref.watch(allSosProvider);
    ref.watch(floodReportsProvider);
    ref.watch(helpRequestsProvider);
    ref.watch(sheltersProvider);
    Future.microtask(refreshNow);
    return null;
  }

  /// Derives the feed and returns how many *new* alerts appeared (0 when the
  /// data has not changed, which is the common case).
  ///
  /// Derivation is best-effort: a storage failure must not break the screen
  /// that triggered it, so the count comes back as 0 and [lastFailure] explains
  /// why rather than throwing into a refresh gesture.
  Future<int> refreshNow() async {
    try {
      lastFailure = null;
      final created = await ref.read(alertServiceProvider).refresh();
      state = DateTime.now().toUtc();
      return created;
    } on Exception catch (e) {
      lastFailure = e;
      return 0;
    }
  }
}

final alertFeedRefresherProvider =
    NotifierProvider<AlertFeedRefresher, DateTime?>(AlertFeedRefresher.new);