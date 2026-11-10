import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flood_relief/ui/boot/boot_gate.dart';
import 'package:flood_relief/ui/home/home_screen.dart';
import 'package:flood_relief/ui/onboarding/onboarding_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('diag onboarding continue', (tester) async {
    setTestViewport(tester);
    await pumpApp(tester);
    await settle(tester);

    // ignore: avoid_print
    print('after boot: onboarding=${find.byType(OnboardingScreen).evaluate().length} '
        'boot=${find.byType(BootGate).evaluate().length}');

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.ensureVisible(find.text('Continue as affected person'));
    await settle(tester);
    await tester.tap(find.text('Continue as affected person'));
    await settle(tester);

    // ignore: avoid_print
    print('after tap: onboarding=${find.byType(OnboardingScreen).evaluate().length} '
        'home=${find.byType(HomeScreen).evaluate().length}');
    // ignore: avoid_print
    print('visible texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
    // ignore: avoid_print
    print('editable: ${tester.widgetList<EditableText>(find.byType(EditableText)).map((e) => e.controller.text).toList()}');
    final snackbars = find.byType(SnackBar);
    // ignore: avoid_print
    print('snackbars: ${snackbars.evaluate().length}');
    if (snackbars.evaluate().isNotEmpty) {
      // ignore: avoid_print
      print('snackbar text: ${tester.widgetList<Text>(find.descendant(of: snackbars, matching: find.byType(Text))).map((t) => t.data).toList()}');
    }
  });
}