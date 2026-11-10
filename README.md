# FloodRelief

Offline-first flood relief coordination. Emergency SOS relayed over a Bluetooth
mesh, plus local flood reporting, help requests, shelters, emergency contacts
and alerts.

No account, no server, no internet required. Everything the app stores stays on
the device it was entered on.

---

## What it actually does

| Area | Real behaviour in this build |
| --- | --- |
| **SOS** | Created locally first, scored by a deterministic priority engine, then queued for Bluetooth transmission and relayed device-to-device. Acknowledgements are real packets. |
| **Flood reports** | Severity, water depth, affected people, position, optional note. Stored locally. **Not relayed over the mesh.** |
| **Help requests** | Category, priority derived from category + detail, and a real status machine (`pending → acknowledged → inProgress → fulfilled` / `cancelled`). Stored locally. **Not relayed over the mesh.** |
| **Shelters** | Capacity, occupancy, facilities, position, open/closed. Arrivals and departures update occupancy; status is derived from it. |
| **Emergency contacts** | Stored locally. Ships **empty** — the app does not invent hotline numbers. |
| **Rescue teams** | Registered locally with leader, contact, availability and optional base position. Operators sign in by selecting a team; incidents are assigned to these teams. Ships empty in production; add the first team from the rescue login screen or Settings. |
| **Alerts** | Derived from real local data (SOS status changes, critical flood reports, urgent help requests, shelters filling up) plus advisories written by a rescue operator. Never fabricated. |
| **Settings** | Link start/stop, behaviour toggles, location permission, clear local data, and a live diagnostics panel including the recorded error log. |

**Deliberate scope limit:** only SOS packets travel over the Bluetooth mesh. The
packet protocol is `sosId`-centric and the UI says so on the dashboard, on each
report screen, and in Settings — so nobody files a flood report expecting a
responder on another phone to see it.

## Architecture

```
lib/
  main.dart              entry point: global error handlers, then Bootstrap.run
  app/
    bootstrap.dart       constructs storage, repositories, services, BLE, overrides
    app.dart             MaterialApp + the full named-route table
    router.dart          AppRoutes catalogue + AppNav push helpers
    providers.dart       every Riverpod provider in one place
    error_surface.dart   ErrorLog, readable ErrorWidget, global handlers
  core/
    constants/           box names, setting keys, limits
    errors/              AppError hierarchy with human-readable messages
    security/            device identity (AES-256 at rest) + key stores
    utils/               id generation, casting, geo distance, time formatting
  models/                immutable records + enums, each with toMap/fromMap
  repositories/          persistence contracts: Hive impl + in-memory impl
  services/              application logic (SOS, BLE, reports, help, shelters,
                         contacts, alerts, rescue teams, local data, location,
                         speech)
  ui/
    boot/                BootGate: auto-routing first route
    home/                affected-person dashboard
    sos/ rescue/         the pre-existing SOS + rescue flows
    reports/ help/ shelter/ contacts/ alerts/ map/ profile/ settings/
```

Layering rules the code actually follows:

* `models` depend on nothing.
* `repositories` depend on `models` + `core`. Each has a `Hive*Repository` and a
  `Memory*Repository` used by tests.
* `services` depend on repositories. They hold the rules, not the widgets.
* `app/providers.dart` is the only place providers are declared; `bootstrap.dart`
  is the only place they are wired.
* `ui` reads providers and calls services. It never touches Hive.

## Storage

Thirteen Hive boxes. `device` is AES-256 encrypted at rest on a real device;
the rest are plain so they can be inspected.

| Box | Contents |
| --- | --- |
| `device` | device identity (encrypted) |
| `user` | the one local profile |
| `sos` | SOS records |
| `packets` | relayed packet log |
| `outbox` | **queued unsent records** |
| `dupCache` | packet dedupe keys |
| `teams` | rescue teams |
| `settings` | toggles, last known position |
| `floodReports` / `helpRequests` / `shelters` / `contacts` / `alerts` | the field-reporting modules |

`Settings → Clear local data` wipes user-generated data (SOS records, packets,
outbox, reports, requests, alerts, contacts) and **preserves** rescue teams,
shelters, device identity and settings. The confirmation dialog states this
before you commit, and the result snackbar reports the real counts.

## Failure handling

The "silent white screen" class of bug is designed out:

* `installGlobalErrorHandlers` (called first in `main`) routes
  `FlutterError.onError` and `PlatformDispatcher.onError` into a bounded
  in-memory `ErrorLog`, and marks async errors handled so an unawaited future
  cannot kill the isolate.
* `ErrorWidget.builder` is replaced with `readableErrorBuilder`, which renders
  the error text. The default builder is a blank grey box in release builds.
* `BootGate` is the first route and **auto-routes** — it resolves persisted
  state and pushes onboarding, rescue login, rescue dashboard, or home on its
  own. There is no splash that waits for a tap.
* If the persisted state cannot be read at all, the gate shows the failure with
  a retry and a "continue without an account" escape hatch.
* `startNetworking` is bounded by `startLinkTimeout` (20s) so a BLE stack that
  never completes its scan cannot hold the app before `runApp`.
* A failure before `runApp` renders `StartupErrorApp` with the error and stack.
* Settings → Diagnostics shows the live error log, the link state and the
  queued-packet count.

Every list screen renders one of `EmptyState`, `LoadingStateView` or
`ErrorStateView`. A failed read shows an error with a retry — never a zero and
never blank space.

## Running it

```bash
flutter pub get
flutter analyze      # must be clean
flutter test
flutter run          # on a physical Android/iOS device
```

`main.dart` uses the real Bluetooth transport
(`useSimulatedTransport: false`) and does **not** seed demo data or start the
radio at launch — a BLE scan is a privileged action and has to be the user's
explicit choice.

Because production seeds no teams, the first rescue operator registers their
team from **Rescue operator login → Register a rescue team** (or
**Settings → Rescue operations → Rescue teams**), then signs in with it. No
server account is required.

See [`docs/PHASE_PROGRESS.md`](docs/PHASE_PROGRESS.md) for the current phase,
what is complete, and what still needs physical-device verification.

For an end-to-end walkthrough with a simulated mesh, run the tests
(`test/sos_lifecycle_test.dart` drives the complete affected → operator →
resolved workflow) or start a debug build with
`BootstrapOptions(seedDemoData: true, useSimulatedTransport: true)`. When a
simulated mesh is present, Settings shows a **Demo mode** section and the
dashboard shows a demo-panel button. When it is absent, those controls are
replaced by a note explaining why they are unavailable — never a dead switch.

## Tests

`flutter test` runs unit tests for the priority engine, codec, repositories and
services, plus widget tests that boot the real application against temporary
Hive storage and drive the actual screens. The suite includes the complete
cross-role SOS lifecycle (`test/sos_lifecycle_test.dart`) and the rescue-team
registration rules (`test/rescue_team_service_test.dart`).

Because `LinkStatusBanner` deliberately animates forever while the radio
scans, screens that run the link use `settle(tester)` from
`test/helpers/test_app.dart` — bounded pumps — instead of `pumpAndSettle`,
which would wait for a frame that never arrives.

## Known limitations

* **Multi-device BLE has not been verified on physical hardware.** The routing
  and acknowledgement logic is real and covered by the simulated mesh; two real
  phones relaying an SOS is untested.
* **Only SOS packets are relayed.** See the scope limit above.
* **No dialler is bundled.** Emergency contacts can be copied but not dialled
  from inside the app (`url_launcher` is not a dependency).
* **No speech input.** `UnavailableSpeechService` is wired; typing works
  everywhere.
* **No backend sync.** `DisabledRemoteSyncService` is wired and local data is
  authoritative. A FastAPI/Postgres contract exists but is off.
* **BLE transport is not end-to-end encrypted.**

Verify any emergency action. This is a coordination aid, not a substitute for
official emergency services.
