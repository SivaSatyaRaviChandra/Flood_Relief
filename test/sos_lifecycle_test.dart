/// The complete SOS lifecycle, end to end, across both roles.
///
///   affected user → creates SOS → rescue operator sees it → acknowledges →
///   assigns a team → starts the rescue → resolves it
///
/// This is the cross-role workflow the app exists for, and it is the one that
/// the per-class unit tests cannot prove: those check the status machine in
/// isolation and the widget tests check that seeded fixtures *render*. This
/// test drives the real screens, the real [SosService] and the real priority
/// engine from the first tap to the final status chip.
///
/// Storage note: SOS reads *and* writes are routed through
/// [MemorySosRepository] (see [pumpApp]). Hive file I/O never completes inside
/// `testWidgets`' fake-async zone, so an operator tapping "Acknowledge" against
/// the Hive-backed repository would hang forever. Rescue teams stay on Hive
/// (read-only), so the team list is the real seeded one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';
import 'helpers/test_app.dart';

void main() {
  void p(String m) {
    // ignore: avoid_print
    print('LIFECYCLE: $m');
  }

  /// Walks the auto-routing boot gate → onboarding → affected-person home.
  ///
  /// [BootGate] routes by itself; there is no "Get started" tap any more, so
  /// the only thing to wait for is the onboarding screen appearing.
  Future<void> signInAsAffected(WidgetTester tester, String name) async {
    await settle(tester);
    expect(find.text('I am joining as:'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), name);
    await tester.ensureVisible(find.text('Continue as affected person'));
    await settle(tester);
    await tester.tap(find.text('Continue as affected person'));
    await settle(tester);
  }

  /// Walks onboarding → rescue login → dashboard for [teamName].
  Future<void> signInAsOperator(
    WidgetTester tester,
    String teamName,
  ) async {
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'Op');
    await tester.tap(find.text('Rescue team'));
    await tester.pump();
    await tester.ensureVisible(find.text('Continue as rescue operator'));
    await settle(tester);
    await tester.tap(find.text('Continue as rescue operator'));
    await settle(tester);
    expect(find.text('Rescue operator login'), findsOneWidget);
    await tester.tap(find.text(teamName));
    await settle(tester);
    await tester.tap(find.text('Open rescue dashboard'));
    await settle(tester);
  }

  /// Taps the "+" of the counter field at [index], [times] times.
  Future<void> bumpCounter(
    WidgetTester tester,
    int index,
    int times,
  ) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byIcon(Icons.add_circle_outline).at(index));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'affected user sends an SOS, rescue operator takes it through to resolved',
    (tester) async {
      setTestViewport(tester);
      // Seeded so rescue teams exist for assignment. The SOS box is overridden
      // with an empty in-memory repository, so the dashboard starts empty and
      // anything it shows must have been created by this test.
      final diagRepo = MemorySosRepository();
      await pumpApp(
        tester,
        seedDemoData: true,
        // Teams are seeded, but demo SOSs are not: this test creates the only
        // incident itself and must be able to count it.
        demoModeOverride: false,
        sosRepository: diagRepo,
      );
      p('pumped app');

      // ---------------------------------------------------------------------
      // 1. USER: creates the SOS through the wizard
      // ---------------------------------------------------------------------
      await signInAsAffected(tester, 'Ana');
      p('signed in as affected');

      await tester.tap(find.text('SEND SOS'));
      await tester.pumpAndSettle();
      p('opened SOS wizard');

      // Step 1 — location (the faked fix is applied automatically).
      expect(find.text('Where are you?'), findsOneWidget);
      expect(find.textContaining('17.70000, 83.30000'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      p('step 1 -> 2');

      // Step 2 — people: 1 → 4 total, 0 → 2 children.
      expect(find.text('How many people are affected?'), findsOneWidget);
      await bumpCounter(tester, 0, 3);
      await bumpCounter(tester, 1, 2);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      p('step 2 -> 3');

      // Step 3 — details. "Rescue required" is the default type.
      await tester.enterText(
        find.byType(TextField).last,
        'Water rising, people trapped on the roof',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      p('step 3 -> 4');

      // Step 4 — review shows the live verdict from the real priority engine.
      expect(find.text('Review & send'), findsOneWidget);
      expect(find.text('4 people affected'), findsOneWidget);
      // base 100 + 1 person 5 + 2 children 6 + keywords 16 = 127 → critical.
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Score 127'), findsOneWidget);

      await tester.tap(find.text('SAVE & TRANSMIT SOS'));
      p('tapped save & transmit');
      // From here on the confirmation screen carries `LinkStatusBanner` in a
      // busy state (a `CircularProgressIndicator` while the radio scans), which
      // never settles — so every step from this point uses bounded pumps.
      await settle(tester);
      p('confirmation settled');

      // ---------------------------------------------------------------------
      // 2. SOS is stored locally, and the app says so honestly
      // ---------------------------------------------------------------------
      expect(find.text('SOS saved on this device'), findsOneWidget);
      final sosId = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((s) => s.startsWith('SOS-'));
      expect(sosId, matches(RegExp(r'^SOS-\d{8}-\w+$')));

      await tester.tap(find.text('Back to home'));
      await settle(tester);
      p('back to home');

      // The SOS was written to the injected repository exactly once.
      final stored = await diagRepo.getAll();
      expect(stored, hasLength(1));
      expect(stored.single.sosId, sosId);

      // The user sees their own active SOS on the home screen.
      expect(find.text(sosId), findsOneWidget);

      // ---------------------------------------------------------------------
      // 3. Switch role: the same device now acts as the rescue operator
      // ---------------------------------------------------------------------
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      await tester.tap(find.text('Switch'));
      await settle(tester);
      await signInAsOperator(tester, 'River Rescue Alpha');

      // ---------------------------------------------------------------------
      // 4. OPERATOR: sees the incoming record with its priority and people count
      // ---------------------------------------------------------------------
      expect(find.text('1 SOS records'), findsOneWidget);
      expect(find.text(sosId), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Rescue Required — 4 people'), findsOneWidget);
      // Shown twice: once as the dashboard status filter, once on the record.
      expect(find.text('Pending'), findsWidgets);

      // ---------------------------------------------------------------------
      // 5. OPERATOR: opens it and works the status machine
      // ---------------------------------------------------------------------
      await tester.tap(find.text(sosId));
      await settle(tester);
      expect(find.text('Rescue actions'), findsOneWidget);

      // The record itself is fully visible to the operator.
      expect(find.text('People'), findsOneWidget);
      expect(find.text('4 affected'), findsOneWidget);
      expect(find.text('Children'), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      // 5a. pending → acknowledged
      await tester.tap(find.text('Acknowledge'));
      await settle(tester);
      expect(find.text('Acknowledged'), findsWidgets);
      expect(find.text('ACK received'), findsOneWidget);

      // 5b. acknowledged → rescueAssigned (only reachable from acknowledged)
      await tester.ensureVisible(find.text('Assign rescue team'));
      await settle(tester);
      await tester.tap(find.text('Assign rescue team'));
      await settle(tester);
      expect(find.text('Assign a rescue team'), findsOneWidget);
      await tester.tap(find.text('River Rescue Alpha').last);
      await settle(tester);
      expect(find.text('Rescue Assigned'), findsWidgets);
      expect(find.text('TEAM-001'), findsOneWidget);

      // 5c. rescueAssigned → inProgress
      await tester.ensureVisible(find.text('Start rescue'));
      await settle(tester);
      await tester.tap(find.text('Start rescue'));
      await settle(tester);
      expect(find.text('In Progress'), findsWidgets);

      // 5d. inProgress → resolved
      await tester.ensureVisible(find.text('Mark resolved'));
      await settle(tester);
      await tester.tap(find.text('Mark resolved'));
      await settle(tester);
      expect(find.text('Resolved'), findsWidgets);

      // The full timeline is recorded for audit.
      expect(find.textContaining('Pending → Acknowledged'), findsOneWidget);
      expect(find.textContaining('Acknowledged → Rescue Assigned'),
          findsOneWidget);
      expect(find.textContaining('Rescue Assigned → In Progress'), findsOneWidget);
      expect(find.textContaining('In Progress → Resolved'), findsOneWidget);

      // ---------------------------------------------------------------------
      // 6. Back on the dashboard: resolved records leave the "Active" view
      // ---------------------------------------------------------------------
      await tester.pageBack();
      await settle(tester);
      expect(find.text('1 SOS records'), findsOneWidget);

      await tester.tap(find.text('Active'));
      await settle(tester);
      expect(find.text('No SOS records in this view.'), findsOneWidget);

      await tester.tap(find.text('All'));
      await settle(tester);
      expect(find.text(sosId), findsOneWidget);
    },
  );
}