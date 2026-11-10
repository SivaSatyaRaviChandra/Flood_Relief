/// Shared test helpers: a fully wired application bootstrap that runs against
/// temporary Hive storage, fake location and no real radio.
///
/// Widget tests run in Flutter's `FakeAsync` zone where Hive's file I/O never
/// completes, so [wireTestApp] must be invoked through `tester.runAsync`.
/// Writes that happen *during* widget interaction (e.g. saving the signed-in
/// user) use [MemoryUserRepository], which completes synchronously.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flood_relief/app/app.dart';
import 'package:flood_relief/app/bootstrap.dart';
import 'package:flood_relief/app/providers.dart';
import 'package:flood_relief/models/app_user.dart';
import 'package:flood_relief/repositories/packet_repository.dart';
import 'package:flood_relief/repositories/rescue_repository.dart';
import 'package:flood_relief/repositories/settings_repository.dart';
import 'package:flood_relief/repositories/sos_repository.dart';
import 'package:flood_relief/repositories/user_repository.dart';
import 'package:flood_relief/services/location_service.dart';
import 'package:flood_relief/services/speech_service.dart';

import 'fakes.dart';

/// Fixed clock used across tests for deterministic output.
final DateTime fixedNow = DateTime.utc(2026, 9, 22, 12, 0, 0);

/// Bootstraps the entire application against a fresh temporary directory.
///
/// * Hive lives in a per-call temp folder (real persistence, no platform).
/// * Location is faked with [FakeLocationService] (no platform channels).
/// * Speech is the unavailable fallback (no plugins).
/// * The simulated mesh transport is used (no BLE hardware).
///
/// **Widget tests must call this inside `tester.runAsync`** because Hive file
/// I/O does not complete in Flutter's fake-async test zone. The matching
/// close is `bootstrap.dispose()`, also inside `tester.runAsync`.
Future<BootstrapResult> wireTestApp({
  bool seedDemoData = false,
  bool? demoModeOverride,
  LocationResult? locationResult,
  UserRepository? userRepository,
  SosRepository? sosRepository,
  SettingsRepository? settingsRepository,
  PacketRepository? packetRepository,
  RescueRepository? rescueRepository,
}) async {
  final dir = await Directory.systemTemp.createTemp('floodrelief_test');
  final bootstrap = await Bootstrap.run(
    BootstrapOptions(
      boxPath: dir.path,
      demoModeOverride: demoModeOverride ?? seedDemoData,
      seedDemoData: seedDemoData,
      autoStartNetworking: false,
      useSimulatedTransport: true,
      userRepository: userRepository,
      sosRepository: sosRepository,
      settingsRepository: settingsRepository,
      packetRepository: packetRepository,
      rescueRepository: rescueRepository,
      locationService: FakeLocationService(
        result: locationResult ??
            LocationSuccess(
              latitude: 17.7000,
              longitude: 83.3000,
              accuracy: 12.0,
              timestamp: fixedNow,
            ),
      ),
      speechService: const UnavailableSpeechService(),
      now: () => fixedNow,
    ),
  );
  return bootstrap;
}

/// Fully in-memory [UserRepository] so widget tests can sign in without any
/// Hive file I/O inside the fake-async test zone.
class MemoryUserRepository implements UserRepository {
  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast();

  @override
  Future<AppUser?> currentUser() async => _user;

  @override
  Future<void> saveUser(AppUser user) async {
    _user = user;
    if (!_controller.isClosed) _controller.add(_user);
  }

  @override
  Future<void> clear() async {
    _user = null;
    if (!_controller.isClosed) _controller.add(null);
  }

  @override
  Stream<AppUser?> watchUser() async* {
    yield _user;
    yield* _controller.stream;
  }

  void dispose() => _controller.close();
}

/// Signs a user in through the real [currentUserProvider] (which writes to
/// [MemoryUserRepository] in tests), inside the provider scope, on the next
/// frame. Wrap the app subtree with this when a screen needs an authenticated
/// user but the test does not want to walk the onboarding flow.
class SignInGate extends ConsumerWidget {
  const SignInGate({super.key, required this.user, required this.child});

  final AppUser user;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future.microtask(() {
      ref.read(currentUserProvider.notifier).signIn(user);
    });
    return child;
  }
}

/// Enlarges the test viewport so long `ListView`-based screens (rescue login,
/// dashboard, wizard steps) build every child instead of culling the ones below
/// the fold of the default 800x600 surface. Reset is automatic per test.
void setTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps a bounded number of frames instead of [WidgetTester.pumpAndSettle].
///
/// Several screens legitimately animate forever: `LinkStatusBanner` shows a
/// `CircularProgressIndicator` while the radio is scanning, which is the
/// correct behaviour for a BLE scan. `pumpAndSettle` waits for *no* scheduled
/// frame, so on those screens it always times out — the failure says nothing
/// about the app.
///
/// This advances [frames] frames of 100 ms each, which is plenty for a
/// navigation transition, a stream emission or a snackbar to appear, and never
/// hangs. Use it wherever the radio is or might be running.
Future<void> settle(
  WidgetTester tester, {
  int frames = 8,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Like [settle] but first gives [WidgetTester.pumpAndSettle] a short window.
///
/// Falls back to bounded pumps when it times out, so a permanently-animating
/// widget is a non-event rather than a test failure.
Future<void> settleIfPossible(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(milliseconds: 1500),
    );
    return;
  } on FlutterError {
    // Timed out waiting for the frame queue to drain: fall through.
  }
  await settle(tester);
}

/// A sample affected user for direct-sign-in tests.
AppUser testAffectedUser({
  String userId = 'USER-TEST01',
  String displayName = 'Test Affected',
}) =>
    AppUser(
      userId: userId,
      displayName: displayName,
      role: UserRole.affected,
      createdAt: fixedNow,
    );

/// A sample rescue operator for direct-sign-in tests.
AppUser testRescueUser({
  String userId = 'RESCUE-TEST01',
  String displayName = 'Test Operator',
  String teamId = 'TEAM-001',
}) =>
    AppUser(
      userId: userId,
      displayName: displayName,
      role: UserRole.rescue,
      teamId: teamId,
      createdAt: fixedNow,
    );

/// The `ErrorWidget.builder` that was installed before any test touched it.
///
/// Captured once, on the first use in the test process, and then reused for the
/// whole run. `FloodReliefApp.materialApp()` calls `installReadableErrorWidget()`
/// when it is *invoked* — that is, while a helper is building the widget tree —
/// so a capture placed anywhere near the `pumpWidget` call is already too late
/// to see the framework default.
ErrorWidgetBuilder? _pristineErrorWidgetBuilder;

/// Records the pristine `ErrorWidget.builder`. Call as the FIRST statement of
/// any helper that pumps the app, before [FloodReliefApp.materialApp] is
/// invoked.
void capturePristineErrorWidgetBuilder() {
  _pristineErrorWidgetBuilder ??= ErrorWidget.builder;
}

/// Puts [capturePristineErrorWidgetBuilder]'s recorded value back, undoing
/// [FloodReliefApp.materialApp]'s process-wide `ErrorWidget.builder` install.
/// Call immediately after pumping the app.
///
/// ## Why the restore must be synchronous
///
/// `flutter_test` snapshots `ErrorWidget.builder` before the test body
/// (`binding.dart:1948`) and verifies it inside `_runTestBody` at
/// `binding.dart:1971` — that is, the moment the body returns, which is
/// **before** any `addTearDown` callback runs. A `tearDown`-only restore is
/// therefore always too late and always fails the framework check. The
/// assignment below has to happen while the body is still running; the
/// `addTearDown` is only a safety net for anything that re-installs a builder
/// later in the same test.
///
/// ## Why `null` cannot be used
///
/// Flutter 3.44.9 declares
/// `static ErrorWidgetBuilder builder = _defaultErrorWidgetBuilder;`
/// (`widgets/framework.dart:5665`). The field is non-nullable and its default
/// is private, so there is neither a way to assign `null` nor a public way to
/// name the default — it can only be captured and replayed.
///
/// The app installs its own builder deliberately: a release build would
/// otherwise render a blank grey box where a screen failed. Every test that
/// pumps the app must therefore put the previous value back, or every widget
/// test fails on the framework check rather than on anything the app did.
void restoreErrorWidgetBuilder() {
  final ErrorWidgetBuilder builderBeforeTest = _pristineErrorWidgetBuilder ??
      (throw StateError(
        'capturePristineErrorWidgetBuilder() must run before '
        'restoreErrorWidgetBuilder().',
      ));
  ErrorWidget.builder = builderBeforeTest;
  addTearDown(() => ErrorWidget.builder = builderBeforeTest);
}

/// Bootstraps the app inside `tester.runAsync`, registers teardown, and pumps
/// the full [FloodReliefApp] (via [FloodReliefApp.materialApp]) with in-memory
/// user *and* settings repositories, so signing in and persisting a setting
/// during the test complete without Hive file I/O.
///
/// Pass [sosRepository] to additionally route **all** SOS reads *and* writes
/// through an in-memory repository. This is required for any test that mutates
/// an SOS from the UI (acknowledge / assign / start / resolve): the bootstrap
/// SOS service writes through the Hive-backed repository, and those writes can
/// never complete inside `testWidgets`' fake-async zone.
///
/// Returns the bootstrap so tests can reach seeded services or directly sign
/// in through a [SignInGate].
Future<BootstrapResult> pumpApp(
  WidgetTester tester, {
  bool seedDemoData = false,
  bool? demoModeOverride,
  MemorySosRepository? sosRepository,
}) async {
  // Must be first: `FloodReliefApp.materialApp` below installs the builder.
  capturePristineErrorWidgetBuilder();

  // Every repository that a test can write to is injected into the bootstrap
  // itself rather than overridden in a nested ProviderScope. A nested scope
  // does not re-create providers that were already initialised in the parent
  // container, so the SOS streams silently kept reading the Hive-backed
  // repository and the end-to-end lifecycle test could never see its own SOS.
  final userRepository = MemoryUserRepository();
  final settingsRepository = MemorySettingsRepository();
  final packetRepository = MemoryPacketRepository();
  final rescueRepository = MemoryRescueRepository();
  final sos = sosRepository ?? MemorySosRepository();

  final bootstrap = await tester.runAsync<BootstrapResult?>(
    () => wireTestApp(
      seedDemoData: seedDemoData,
      demoModeOverride: demoModeOverride,
      userRepository: userRepository,
      settingsRepository: settingsRepository,
      sosRepository: sos,
      packetRepository: packetRepository,
      rescueRepository: rescueRepository,
    ),
  );
  final b = bootstrap!;

  addTearDown(() async {
    await tester.runAsync(() => b.dispose());
    userRepository.dispose();
    sos.dispose();
    packetRepository.dispose();
    rescueRepository.dispose();
  });

  final app = FloodReliefApp.materialApp(b.wrapWithProviders);
  await tester.pumpWidget(app);
  await tester.pump();
  restoreErrorWidgetBuilder();
  return b;
}

/// Convenience for tests that need to pump a single screen wrapped in the
/// real provider scope with an optionally already signed-in user.
Future<void> pumpScaffold(
  WidgetTester tester, {
  required Widget child,
  AppUser? user,
}) async {
  // Must be first: anything pumped below may install a builder.
  capturePristineErrorWidgetBuilder();
  final userRepository = MemoryUserRepository();
  final settingsRepository = MemorySettingsRepository();
  final rescueRepository = MemoryRescueRepository();
  final bootstrap = await tester.runAsync<BootstrapResult?>(
    () => wireTestApp(
      userRepository: userRepository,
      settingsRepository: settingsRepository,
      sosRepository: MemorySosRepository(),
      packetRepository: MemoryPacketRepository(),
      rescueRepository: rescueRepository,
    ),
  );
  final b = bootstrap!;

  addTearDown(() async {
    await tester.runAsync(() => b.dispose());
    userRepository.dispose();
    rescueRepository.dispose();
  });

  final wrapped = b.wrapWithProviders(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: user == null ? child : SignInGate(user: user, child: child),
    ),
  );
  await tester.pumpWidget(wrapped);
  await tester.pump();
  restoreErrorWidgetBuilder();
}