/// Named route catalogue for the application.
///
/// Screens that need a parameter receive it through
/// `Navigator.pushNamed(context, route, arguments: ...)` and read it with
/// `ModalRoute.of(context)!.settings.arguments`.
library;

import 'package:flutter/material.dart';

class AppRoutes {
  AppRoutes._();

  /// The auto-routing boot gate. See `ui/boot/boot_gate.dart`.
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String createSos = '/create-sos';
  static const String sosConfirmation = '/sos-confirmation';
  static const String mySos = '/my-sos';
  static const String sosDetails = '/sos-details';
  static const String settings = '/settings';
  static const String rescueLogin = '/rescue-login';
  static const String rescueDashboard = '/rescue-dashboard';
  static const String rescueMap = '/rescue-map';
  static const String rescueTeams = '/rescue-teams';
  static const String demoPanel = '/demo-panel';

  // Field reporting and response.
  static const String reportFlood = '/report-flood';
  static const String floodReports = '/flood-reports';
  static const String requestHelp = '/request-help';
  static const String helpRequests = '/help-requests';
  static const String helpRequestDetails = '/help-request-details';
  static const String shelters = '/shelters';
  static const String shelterDetails = '/shelter-details';
  static const String contacts = '/emergency-contacts';
  static const String alerts = '/alerts';
  static const String profile = '/profile';
  static const String situationMap = '/situation-map';
}

/// Convenience helpers so widgets do not repeat argument plumbing.
class AppNav {
  AppNav._();

  /// Push a route. The [sosId] is passed for detail screens.
  static Future<T?> pushSosDetails<T>(
    BuildContext context,
    String sosId,
  ) {
    return Navigator.of(context).pushNamed<T>(
      AppRoutes.sosDetails,
      arguments: sosId,
    );
  }

  static Future<T?> pushShelterDetails<T>(
    BuildContext context,
    String shelterId,
  ) {
    return Navigator.of(context).pushNamed<T>(
      AppRoutes.shelterDetails,
      arguments: shelterId,
    );
  }

  static Future<T?> pushHelpRequestDetails<T>(
    BuildContext context,
    String requestId,
  ) {
    return Navigator.of(context).pushNamed<T>(
      AppRoutes.helpRequestDetails,
      arguments: requestId,
    );
  }

  static Future<T?> pushNamed<T>(
    BuildContext context,
    String route, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamed<T>(route, arguments: arguments);
  }

  /// Replaces the whole stack — used when switching role or signing out.
  static void replaceAll(BuildContext context, String route) {
    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
  }
}