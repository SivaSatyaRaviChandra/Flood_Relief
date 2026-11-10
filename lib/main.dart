import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/error_surface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Installed *before* anything else can throw. An error that escapes
  // `FlutterError.onError` or an unawaited future kills the isolate and leaves
  // the last frame on screen forever — which is exactly the silent white
  // screen this app must not have.
  installGlobalErrorHandlers(
    log: errorLog,
    onReport: (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('FloodRelief error: $error\n$stackTrace');
      }
    },
  );

  // Startup failures (missing platform plugins, storage errors, ...) must
  // never leave a silent white screen: report the exception and build a
  // visible error surface instead of letting the future die unhandled
  // before `runApp`.
  final BootstrapResult bootstrap;
  try {
    bootstrap = await Bootstrap.run(
      // Production defaults. The simulated mesh and the demo data set are
      // opt-in from the demo panel, and the radio is never powered on at
      // startup: a BLE scan is a privileged action and must be the user's
      // explicit choice.
      const BootstrapOptions(
        useSimulatedTransport: false,
        seedDemoData: false,
        demoModeOverride: false,
        autoStartNetworking: false,
      ),
    );
  } catch (error, stackTrace) {
    errorLog.record(error, stackTrace, source: 'bootstrap');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'FloodRelief bootstrap',
        context: ErrorDescription('while initialising application storage'),
      ),
    );
    runApp(StartupErrorApp(error: error, stackTrace: stackTrace));
    return;
  }

  runApp(FloodReliefApp(bootstrap: bootstrap));
}
