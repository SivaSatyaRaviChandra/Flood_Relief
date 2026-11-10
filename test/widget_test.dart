/// End-to-end widget tests over the real (wired) application.
///
/// These run the full bootstrap against temporary Hive storage inside
/// `tester.runAsync` (Hive file I/O never completes in `testWidgets`' fake
/// async zone) and sign in through the in-memory user repository override.
///
/// Two things worth knowing about these tests:
///  * the app now auto-routes through [BootGate], so there is no "Get started"
///    tap — the gate sends an unauthenticated launch to onboarding by itself;
///  * screens that run the radio show a permanently animating
///    `LinkStatusBanner`, so they use [settle] (bounded pumps) rather than
///    `pumpAndSettle`, which would wait forever for a frame that never comes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('boot gate auto-routes to onboarding, then to the dashboard',
      (tester) async {
    setTestViewport(tester);
    await pumpApp(tester);

    // No tap required: the gate decides on its own. A splash that needed a
    // manual "Get started" press is exactly the dead end this test guards
    // against.
    await settle(tester);
    expect(find.text('I am joining as:'), findsOneWidget);

    // Onboarding: enter a name, keep the default "affected" role.
    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.ensureVisible(find.text('Continue as affected person'));
    await settle(tester);
    await tester.tap(find.text('Continue as affected person'));
    await settle(tester);

    // Affected dashboard.
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('SEND SOS'), findsOneWidget);
    expect(find.text('My active SOSs'), findsOneWidget);
    expect(find.text('No active SOSs yet.'), findsOneWidget);

    // The dashboard offers every module, each of which is a real route.
    for (final label in [
      'Report flooding',
      'Request help',
      'Find a shelter',
      'Emergency contacts',
      'Alerts',
      'My profile',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
  });

  testWidgets('every dashboard quick action opens a real screen', (tester) async {
    setTestViewport(tester);
    await pumpApp(tester);
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.ensureVisible(find.text('Continue as affected person'));
    await settle(tester);
    await tester.tap(find.text('Continue as affected person'));
    await settle(tester);

    // Report flooding.
    await tester.ensureVisible(find.text('Report flooding'));
    await tester.tap(find.text('Report flooding'));
    await settle(tester);
    expect(find.text('Report flooding', skipOffstage: false), findsWidgets);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // Request help.
    await tester.ensureVisible(find.text('Request help'));
    await tester.tap(find.text('Request help'));
    await settle(tester);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // Shelters.
    await tester.ensureVisible(find.text('Find a shelter'));
    await tester.tap(find.text('Find a shelter'));
    await settle(tester);
    expect(find.text('No shelters'), findsWidgets);
    await tester.pageBack();
    await settle(tester);

    // Contacts.
    await tester.ensureVisible(find.text('Emergency contacts'));
    await tester.tap(find.text('Emergency contacts'));
    await settle(tester);
    expect(find.text('No emergency contacts'), findsWidgets);
    await tester.pageBack();
    await settle(tester);

    // Alerts.
    await tester.ensureVisible(find.text('Alerts'));
    await tester.tap(find.text('Alerts'));
    await settle(tester);
    expect(find.text('No alerts'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // Profile.
    await tester.ensureVisible(find.text('My profile'));
    await tester.tap(find.text('My profile'));
    await settle(tester);
    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('create-SOS wizard reaches review without transmitting',
      (tester) async {
    setTestViewport(tester);
    await pumpApp(tester);

    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.ensureVisible(find.text('Continue as affected person'));
    await settle(tester);
    await tester.tap(find.text('Continue as affected person'));
    await settle(tester);

    await tester.tap(find.text('SEND SOS'));
    await settle(tester);

    // Step 1 — location.
    expect(find.text('Where are you?'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settle(tester);

    // Step 2 — people (defaults valid: 1 total person).
    expect(find.text('How many people are affected?'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settle(tester);

    // Step 3 — details: Next stays disabled until a description exists.
    final nextButton = find.widgetWithText(FilledButton, 'Next');
    expect(tester.widget<FilledButton>(nextButton).onPressed, isNull);
    await tester.enterText(
      find.byType(TextField).last,
      'Water rising, people trapped on the roof',
    );
    await settle(tester);
    // The details TextField keeps a focused input connection whose per-frame
    // caret post-frame callbacks fire across the pumped step transition and
    // trip render-object assertions when the step unmounts mid-fade. Mirror
    // real UX (tapping Next drops focus) before moving on.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);

    // Step 4 — review. Assert the send affordance exists but never tap it.
    expect(find.text('Review & send'), findsOneWidget);
    expect(find.text('SAVE & TRANSMIT SOS'), findsOneWidget);
  });

  testWidgets('rescue operator sees seeded demo SOSs on the dashboard',
      (tester) async {
    setTestViewport(tester);
    await pumpApp(tester, seedDemoData: true);

    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'Op');
    await tester.tap(find.text('Rescue team'));
    await tester.pump();
    await tester.ensureVisible(find.text('Continue as rescue operator'));
    await settle(tester);
    await tester.tap(find.text('Continue as rescue operator'));
    await settle(tester);

    // Rescue login: pick a seeded team, then enter.
    expect(find.text('Rescue operator login'), findsOneWidget);
    await tester.tap(find.text('River Rescue Alpha'));
    await settle(tester);
    await tester.tap(find.text('Open rescue dashboard'));
    await settle(tester);

    // Dashboard shows the seeded fixtures.
    expect(find.text('3 SOS records'), findsOneWidget);
    expect(find.text('SOS-20260922-000001'), findsOneWidget);
    expect(find.text('River Rescue Alpha'), findsOneWidget);
    expect(find.text('Medical Rapid Charlie'), findsOneWidget);
  });
}
