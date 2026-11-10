import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('probe seeded boot', (tester) async {
    setTestViewport(tester);
    // ignore: avoid_print
    print('PROBE: before pumpApp');
    final repo = MemorySosRepository();
    await pumpApp(
      tester,
      seedDemoData: true,
      demoModeOverride: false,
      sosRepository: repo,
    );
    // ignore: avoid_print
    print('PROBE: after pumpApp');
    await settle(tester);
    // ignore: avoid_print
    print('PROBE: after settle: joining=${find.text('I am joining as:').evaluate().length}');
  });
}
