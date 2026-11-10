/// Affected-user home: the situation dashboard plus the SEND SOS action.
///
/// The dashboard shows only what is really stored on this device. Every number
/// comes from a Riverpod provider over local Hive data — nothing is estimated,
/// fetched, or invented — and a failed read renders an error row with a retry
/// rather than silently showing zero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/enums/alert_severity.dart';
import '../widgets/badges.dart';
import '../widgets/sos_card.dart';
import '../widgets/state_views.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;

    // A rescue operator who lands here (deep link, role switch) is sent to the
    // console rather than shown an affected-person dashboard.
    if (user != null && user.isRescue) {
      return const _RescueShortcut();
    }

    final mySos = ref.watch(mySosProvider);
    final linkStatus = ref.watch(communicationStatusProvider).value;
    final unreadAlerts = ref.watch(unreadAlertsProvider).value ?? 0;
    final showBanner = ref.watch(showAlertBannerProvider).value ?? true;
    final topSeverity = ref.watch(topAlertSeverityProvider);
    final pending = ref.watch(pendingPacketCountProvider).value ?? 0;
    final active = mySos.value?.where((s) => s.status.isActive).toList() ??
        const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.displayName ?? 'FloodRelief'),
        actions: [
          _AlertButton(count: unreadAlerts),
          // Only offered when a simulated mesh was actually built. A dead
          // button that opens an empty screen is worse than no button.
          if (ref.watch(demoControllerProvider) != null)
            IconButton(
              icon: const Icon(Icons.science_outlined),
              tooltip: 'Demo panel',
              onPressed: () => AppNav.pushNamed(context, AppRoutes.demoPanel),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => AppNav.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Streams re-emit on their own; invalidating the derived futures is
          // what actually recomputes the dashboard numbers.
          ref.invalidate(unreadAlertsProvider);
          ref.invalidate(pendingPacketCountProvider);
          ref.invalidate(situationSummaryProvider);
          await ref.read(alertFeedRefresherProvider.notifier).refreshNow();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 8),
            LinkStatusBanner(status: linkStatus),
            if (showBanner && topSeverity != null)
              _AlertBanner(severity: topSeverity, count: unreadAlerts),
            const SizedBox(height: 4),
            if (pending > 0)
              CapabilityNote(
                icon: Icons.outbox_outlined,
                text: '$pending packet${pending == 1 ? ' is' : 's are'} queued '
                    'to be transmitted. They are saved and will be retried as '
                    'soon as the radio is available.',
              ),
            const SizedBox(height: 4),
            const _SendSosButton(),
            const SizedBox(height: 14),
            const _SituationPanel(),
            const SizedBox(height: 8),
            const _QuickActions(),
            const SizedBox(height: 14),
            const _HelpScreenNote(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'My active SOSs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        AppNav.pushNamed(context, AppRoutes.mySos),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            for (final sos in active.take(4))
              SosCard(
                request: sos,
                onTap: () => AppNav.pushSosDetails(context, sos.sosId),
              ),
            if (active.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'No active SOSs yet.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// App-bar alert button with a real unread badge.
class _AlertButton extends StatelessWidget {
  const _AlertButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_none),
      ),
      tooltip: count == 0 ? 'Alerts' : 'Alerts ($count unread)',
      onPressed: () => AppNav.pushNamed(context, AppRoutes.alerts),
    );
  }
}

/// Banner shown above the dashboard when unread alerts exist and the user has
/// not switched the banner off in Settings.
class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.severity, required this.count});

  final AlertSeverity severity;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = alertSeverityColor(severity);
    return InkWell(
      onTap: () => AppNav.pushNamed(context, AppRoutes.alerts),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_active_outlined, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count unread alert${count == 1 ? '' : 's'} · highest '
                'severity ${severity.label.toLowerCase()}.',
                style: TextStyle(fontSize: 12.5, color: color),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SendSosButton extends StatelessWidget {
  const _SendSosButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: () => AppNav.pushNamed(context, AppRoutes.createSos),
            style: FilledButton.styleFrom(
              backgroundColor: kDangerColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(72),
              textStyle: const TextStyle(fontSize: 20),
            ),
            icon: const Icon(Icons.sos, size: 32),
            label: const Text('SEND SOS'),
          ),
          const SizedBox(height: 8),
          Text(
            'Saved on this device first, then relayed through nearby devices '
            'on a Bluetooth mesh. No internet needed.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "what is happening" grid, derived entirely from local records.
class _SituationPanel extends ConsumerWidget {
  const _SituationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(situationSummaryProvider);
    final reportsAsync = ref.watch(floodReportsProvider);
    final requestsAsync = ref.watch(helpRequestsProvider);

    // A failed read must be visible. Rendering zeros here would be a lie.
    final failure = [
      if (reportsAsync.hasError) 'flood reports',
      if (requestsAsync.hasError) 'help requests',
    ].join(' and ');
    if (failure.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: ErrorStateView(
          title: 'Could not read $failure',
          error: reportsAsync.hasError
              ? reportsAsync.error!
              : requestsAsync.error!,
          onRetry: () {
            ref.invalidate(floodReportsProvider);
            ref.invalidate(helpRequestsProvider);
            ref.invalidate(situationSummaryProvider);
          },
        ),
      );
    }

    if (summary == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingStateView(message: 'Reading local records...'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'Situation on this device',
        subtitle: summary.headline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // Three columns is unreadable on a narrow phone, so the grid
                // reflows instead of clipping.
                final columns = constraints.maxWidth < 380 ? 2 : 3;
                final tileWidth =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: StatTile(
                        label: 'Active SOSs',
                        value: '${summary.activeSos}',
                        icon: Icons.sos,
                        color: summary.activeSos > 0 ? kDangerColor : null,
                        onTap: () =>
                            AppNav.pushNamed(context, AppRoutes.mySos),
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: StatTile(
                        label: 'Open help requests',
                        value: '${summary.openHelpRequests}',
                        icon: Icons.volunteer_activism_outlined,
                        color: summary.openHelpRequests > 0
                            ? const Color(0xFFEF6C00)
                            : null,
                        onTap: () =>
                            AppNav.pushNamed(context, AppRoutes.helpRequests),
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: StatTile(
                        label: 'Shelters with space',
                        value:
                            '${summary.sheltersWithSpace}/${summary.sheltersTotal}',
                        icon: Icons.home_work_outlined,
                        color: const Color(0xFF2E7D32),
                        onTap: () =>
                            AppNav.pushNamed(context, AppRoutes.shelters),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              _floodSentence(summary),
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  AppNav.pushNamed(context, AppRoutes.situationMap),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open situation map'),
            ),
          ],
        ),
      ),
    );
  }

  /// Plain sentence about recent flood reports. Counts only reports inside the
  /// freshness window, because an old report does not describe current water.
  static String _floodSentence(SituationSummary summary) {
    final hours = Limits.floodReportFreshness.inHours;
    if (summary.freshFloodReports == 0) {
      return 'No flood report filed in the last $hours hours.';
    }
    final reports = summary.freshFloodReports;
    final people = summary.peopleInFloodReports;
    final peak = summary.peakFloodSeverity;
    final buffer = StringBuffer(
      '$reports flood report${reports == 1 ? '' : 's'} in the last $hours hours '
      'covering $people ${people == 1 ? 'person' : 'people'}',
    );
    if (peak != null) {
      buffer.write(' · peak severity ${peak.label.toLowerCase()}');
    }
    buffer.write('.');
    return buffer.toString();
  }
}

/// The six things a person in a flood actually needs, one tap each.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'What do you need?',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  AppNav.pushNamed(context, AppRoutes.reportFlood),
              icon: const Icon(Icons.water_drop_outlined, size: 18),
              label: const Text('Report flooding'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  AppNav.pushNamed(context, AppRoutes.requestHelp),
              icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
              label: const Text('Request help'),
            ),
            OutlinedButton.icon(
              onPressed: () => AppNav.pushNamed(context, AppRoutes.shelters),
              icon: const Icon(Icons.home_work_outlined, size: 18),
              label: const Text('Find a shelter'),
            ),
            OutlinedButton.icon(
              onPressed: () => AppNav.pushNamed(context, AppRoutes.contacts),
              icon: const Icon(Icons.contact_phone_outlined, size: 18),
              label: const Text('Emergency contacts'),
            ),
            OutlinedButton.icon(
              onPressed: () => AppNav.pushNamed(context, AppRoutes.alerts),
              icon: const Icon(Icons.notifications_outlined, size: 18),
              label: const Text('Alerts'),
            ),
            OutlinedButton.icon(
              onPressed: () => AppNav.pushNamed(context, AppRoutes.profile),
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('My profile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// States plainly that field reports are local-only in this build, so nobody
/// reports a flood expecting a rescue operator on another device to see it.
class _HelpScreenNote extends StatelessWidget {
  const _HelpScreenNote();

  @override
  Widget build(BuildContext context) {
    return const CapabilityNote(
      icon: Icons.info_outline,
      text: 'Flood reports and help requests are stored on this device and '
          'listed in the app. Only SOSs travel over the Bluetooth mesh in '
          'this build, so a report filed here is not seen by other phones — '
          'show this screen to a rescue operator in person.',
    );
  }
}

class _RescueShortcut extends ConsumerWidget {
  const _RescueShortcut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(user?.displayName ?? 'Rescue operator')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.health_and_safety,
              size: 64,
              color: Color(0xFF2E7D32),
            ),
            const SizedBox(height: 12),
            const Text(
              'You are signed in as a rescue operator.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.rescueDashboard,
                (route) => false,
              ),
              child: const Text('Open rescue dashboard'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.onboarding,
                (route) => false,
              ),
              child: const Text('Sign out / switch role'),
            ),
          ],
        ),
      ),
    );
  }
}
