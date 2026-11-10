import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  test('bootstrap dispose completes', () async {
    final b = await wireTestApp();
    // ignore: avoid_print
    print('PROBE: bootstrapped');
    await b.dispose().timeout(const Duration(seconds: 10));
    // ignore: avoid_print
    print('PROBE: disposed');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
