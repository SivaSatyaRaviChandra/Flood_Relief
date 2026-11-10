/// The FloodRelief application root.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bootstrap.dart';
import 'error_surface.dart';
import 'router.dart';
import 'theme.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/boot/boot_gate.dart';
import '../ui/contacts/contacts_screen.dart';
import '../ui/demo/demo_panel_screen.dart';
import '../ui/help/help_requests_screen.dart';
import '../ui/help/request_help_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/map/situation_map_screen.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../ui/profile/profile_screen.dart';
import '../ui/reports/flood_reports_screen.dart';
import '../ui/reports/report_flood_screen.dart';
import '../ui/rescue/rescue_dashboard_screen.dart';
import '../ui/rescue/rescue_login_screen.dart';
import '../ui/rescue/rescue_map_screen.dart';
import '../ui/rescue/rescue_teams_screen.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/shelter/shelters_screen.dart';
import '../ui/sos/create_sos_screen.dart';
import '../ui/sos/my_sos_screen.dart';
import '../ui/sos/sos_confirmation_screen.dart';
import '../ui/sos/sos_details_screen.dart';

class FloodReliefApp extends StatelessWidget {
  const FloodReliefApp({super.key, required this.bootstrap});

  final BootstrapResult bootstrap;

  /// Builds the application root [MaterialApp] with every route registered.
  ///
  /// [wrap] is applied around the [MaterialApp] so tests can inject extra
  /// Riverpod overrides *inside* the bootstrap scope without touching
  /// production wiring.
  ///
  /// Two failure-mode guards live here:
  ///  * [AppRoutes.splash] is the auto-routing [BootGate], not a dead-end
  ///    splash that needed a manual tap;
  ///  * `ErrorWidget.builder` is [readableErrorBuilder] (installed by
  ///    `installReadableErrorWidget` in `main`), so a screen that throws while
  ///    building renders a readable card instead of a bare red box (debug) or a
  ///    blank grey box (release).
  static Widget materialApp(Widget Function(Widget child) wrap) {
    installReadableErrorWidget();
    return wrap(
      MaterialApp(
        title: 'FloodRelief',
        debugShowCheckedModeBanner: false,
        theme: buildFloodReliefTheme(Brightness.light),
        darkTheme: buildFloodReliefTheme(Brightness.dark),
        initialRoute: AppRoutes.splash,
        routes: {
          AppRoutes.splash: (_) => const BootGate(),
          AppRoutes.onboarding: (_) => const OnboardingScreen(),
          AppRoutes.home: (_) => const HomeScreen(),
          AppRoutes.createSos: (_) => const CreateSosScreen(),
          AppRoutes.sosConfirmation: (_) => const SosConfirmationScreen(),
          AppRoutes.mySos: (_) => const MySosScreen(),
          AppRoutes.sosDetails: (_) => const SosDetailsScreen(),
          AppRoutes.settings: (_) => const SettingsScreen(),
          AppRoutes.rescueLogin: (_) => const RescueLoginScreen(),
          AppRoutes.rescueDashboard: (_) => const RescueDashboardScreen(),
          AppRoutes.rescueMap: (_) => const RescueMapScreen(),
          AppRoutes.rescueTeams: (_) => const RescueTeamsScreen(),
          AppRoutes.demoPanel: (_) => const DemoPanelScreen(),

          // Field reporting and response.
          AppRoutes.reportFlood: (_) => const ReportFloodScreen(),
          AppRoutes.floodReports: (_) => const FloodReportsScreen(),
          AppRoutes.requestHelp: (_) => const RequestHelpScreen(),
          AppRoutes.helpRequests: (_) => const HelpRequestsScreen(),
          AppRoutes.helpRequestDetails: (_) => const HelpRequestDetailsScreen(),
          AppRoutes.shelters: (_) => const SheltersScreen(),
          AppRoutes.shelterDetails: (_) => const ShelterDetailsScreen(),
          AppRoutes.contacts: (_) => const ContactsScreen(),
          AppRoutes.alerts: (_) => const AlertsScreen(),
          AppRoutes.profile: (_) => const ProfileScreen(),
          AppRoutes.situationMap: (_) => const SituationMapScreen(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    return materialApp(bootstrap.wrapWithProviders);
  }
}

/// Shown when [Bootstrap.run] fails before the real app root can be built.
///
/// Without this, an exception thrown before `runApp` leaves the engine
/// rendering nothing — a silent white screen. This surface reports the
/// failure (and stack trace) so startup problems are diagnosable on-device.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FloodRelief — startup error',
      debugShowCheckedModeBanner: false,
      theme: buildFloodReliefTheme(Brightness.light),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('FloodRelief could not start'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Startup failed before the UI could be wired.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('$error',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.error,
                      )),
              const SizedBox(height: 16),
              const Text('Stack trace:'),
              const SizedBox(height: 4),
              Text(
                '$stackTrace',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}