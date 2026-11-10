/// Settings: link control, behaviour toggles, location permission, storage,
/// diagnostics, and honest capability notes.
///
/// Two rules run through the whole screen:
///  * a control is only rendered when it can actually do something — the demo
///    switch appears only when a simulated mesh was built, and the "open system
///    settings" button reports honestly when the platform has no such screen;
///  * every read that can fail is rendered as a failure with a retry, never as a
///    zero or an empty list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../services/ble/ble_service.dart';
import '../../services/location_service.dart';
import '../boot/boot_gate.dart' show showErrorLogDialog;
import '../widgets/badges.dart';
import '../widgets/state_views.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = ref.watch(deviceIdProvider);
    final linkStatus = ref.watch(communicationStatusProvider).value;
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Peer-to-peer link'),
          LinkStatusBanner(status: linkStatus),
          const _LinkControls(),
          const _SectionHeader('Behaviour'),
          _ToggleTile(
            provider: autoStartLinkAfterSosProvider,
            icon: Icons.play_circle_outline,
            title: 'Start the link after sending an SOS',
            subtitle: 'Requests Bluetooth permission only when you press SEND '
                'SOS, not at app start.',
          ),
          _ToggleTile(
            provider: showAlertBannerProvider,
            icon: Icons.notifications_outlined,
            title: 'Show the alert banner on the dashboard',
            subtitle: 'Off hides the banner. The Alerts screen is still '
                'reachable from the dashboard at all times.',
          ),
          const _SectionHeader('Location'),
          const _LocationTile(),
          const _SectionHeader('Rescue operations'),
          _ActionTile(
            icon: Icons.groups_outlined,
            title: 'Rescue teams',
            subtitle: 'Register teams, update their availability and base '
                'location. Incidents are assigned to these teams.',
            onTap: () => AppNav.pushNamed(context, AppRoutes.rescueTeams),
          ),
          const _SectionHeader('Storage'),
          const _StorageCard(),
          const _SectionHeader('Diagnostics'),
          const _DiagnosticsCard(),
          const _SectionHeader('Identity'),
          _InfoTile(
            icon: Icons.devices,
            title: 'Device ID',
            subtitle: deviceId,
          ),
          _InfoTile(
            icon: Icons.person_outline,
            title: 'Signed in as',
            subtitle: user == null
                ? 'Not signed in'
                : '${user.displayName} (${user.role.label})'
                    '${user.teamId == null ? '' : ' · team ${user.teamId}'}',
            trailing: TextButton(
              onPressed: () => AppNav.replaceAll(context, AppRoutes.onboarding),
              child: const Text('Switch'),
            ),
          ),
          _ActionTile(
            icon: Icons.person_outline,
            title: 'My profile',
            subtitle: 'Switch role, sign out, storage footprint',
            onTap: () => AppNav.pushNamed(context, AppRoutes.profile),
          ),
          const _SectionHeader('Demo mode'),
          const _DemoModeCard(),
          const _SectionHeader('Capabilities (honest notes)'),
          const _NoteTile(
            icon: Icons.bluetooth,
            title: 'Bluetooth mesh — SOS only',
            body: 'SOS packets hop device-to-device over Bluetooth, typically '
                'tens of metres indoors. Multi-hop routing is implemented in '
                'software but has not been verified on physical multi-device '
                'hardware. Flood reports, help requests and alerts are stored '
                'on this device only; they are NOT relayed over the mesh.',
          ),
          const _NoteTile(
            icon: Icons.wifi_off,
            title: 'No internet required',
            body: 'The app is offline-first. It never needs Wi-Fi or mobile '
                'data to save or transmit SOSs.',
          ),
          const _NoteTile(
            icon: Icons.mic_off_outlined,
            title: 'Voice input',
            body: 'On-device speech recognition (Vosk) is optional and not '
                'bundled in this build; typing works everywhere.',
          ),
          const _NoteTile(
            icon: Icons.cloud_off_outlined,
            title: 'Backend sync',
            body: 'A FastAPI/Postgres sync contract exists but is disabled by '
                'default. Local data is authoritative.',
          ),
          const _NoteTile(
            icon: Icons.phone_disabled_outlined,
            title: 'Dialling a contact',
            body: 'Emergency contacts are stored and shown, but this build '
                'does not bundle a dialler, so the Call action only copies the '
                'number for you to paste into your phone app.',
          ),
          const _NoteTile(
            icon: Icons.lock_outline,
            title: 'Storage',
            body: 'Device identity is encrypted at rest (AES-256). SOS records '
                'are stored in plain Hive boxes for inspection. BLE transport '
                'is not end-to-end encrypted.',
          ),
          const _SectionHeader('About'),
          const _InfoTile(
            icon: Icons.emergency_share,
            title: 'FloodRelief',
            subtitle: 'Offline-first flood SOS & rescue coordination.\n'
                'MIT-style, no warranty. Verify any emergency action.',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Link
// ---------------------------------------------------------------------------

/// Start / stop with the real state, so a link that is already running offers
/// "stop" rather than a second "start" that would throw.
class _LinkControls extends ConsumerWidget {
  const _LinkControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(communicationStatusProvider);
    final current = status.value;

    if (status.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: ErrorStateView(
          title: 'Could not read the link state',
          error: status.error!,
          onRetry: () => ref.invalidate(communicationStatusProvider),
        ),
      );
    }

    final busy = current != null &&
        (current.state == CommunicationState.starting ||
            current.state == CommunicationState.relaySearching ||
            current.state == CommunicationState.attempting);

    return Column(
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The radio is working. Stop it if you need the battery '
                    'back — the SOS is already saved either way.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _ActionTile(
          icon: Icons.link,
          title: 'Start peer-to-peer link',
          subtitle: 'Requests Bluetooth permissions. SOS packets are '
              'transmitted while it is running.',
          enabled: !busy,
          onTap: () => _run(
            context,
            () => ref.read(networkingProvider).start(requestPermissions: true),
            'Link starting.',
          ),
        ),
        _ActionTile(
          icon: Icons.link_off,
          title: 'Stop peer-to-peer link',
          subtitle: 'Anything already queued stays on this device and is sent '
              'when the link is started again.',
          enabled: current != null &&
              current.state != CommunicationState.idle &&
              current.state != CommunicationState.stopped,
          onTap: () => _run(
            context,
            () => ref.read(networkingProvider).stop(),
            'Link stopped.',
          ),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not do that: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Toggles
// ---------------------------------------------------------------------------

class _ToggleTile extends ConsumerWidget {
  const _ToggleTile({
    required this.provider,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final AsyncNotifierProvider<SettingToggleNotifier, bool> provider;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SwitchListTile(
        // While the initial read is in flight the switch shows the known
        // fallback and is disabled, so it cannot be flipped blind.
        value: value.value ?? false,
        onChanged: value.isLoading
            ? null
            : (v) => _set(context, ref, v),
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool next) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(provider.notifier).set(next);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save that setting: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

class _LocationTile extends ConsumerWidget {
  const _LocationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(locationPermissionProvider);
    final position = ref.watch(lastKnownPositionProvider);
    final locationState = ref.watch(locationStateProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Location permission',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _describe(permission, position, locationState),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Position is used to tag SOSs, flood reports and help requests '
              'so a nearby responder knows where to go. It is never sent to a '
              'server.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: locationState.loading
                      ? null
                      : () => ref.read(locationStateProvider.notifier).reload(),
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Get a fresh fix'),
                ),
                if (permission.value == LocationPermissionState.denied)
                  OutlinedButton.icon(
                    onPressed: () => _requestPermission(context, ref),
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('Allow location'),
                  ),
                if (permission.value ==
                    LocationPermissionState.permanentlyDenied)
                  OutlinedButton.icon(
                    onPressed: () => _openSystemSettings(context, ref),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Open system settings'),
                  ),
                if (permission.hasError)
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(locationPermissionProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(
    AsyncValue<LocationPermissionState> permission,
    ({double lat, double lng})? position,
    LocationState locationState,
  ) {
    if (locationState.loading) return 'Asking the GPS for a position...';
    if (permission.hasError) {
      return 'Could not read the permission: ${permission.error}';
    }
    final state = permission.value;
    if (state == null) return 'Checking permission...';
    return switch (state) {
      LocationPermissionState.granted => position == null
          ? 'Granted, but no position has been captured yet.'
          : 'Granted. Last fix ${position.lat.toStringAsFixed(5)}, '
              '${position.lng.toStringAsFixed(5)}.',
      LocationPermissionState.denied =>
        'Denied. SOSs and reports can still be sent without a position, but a '
            'responder will not know where to go.',
      LocationPermissionState.permanentlyDenied =>
        'Blocked in system settings. It has to be re-enabled there; the app '
            'cannot ask again.',
      LocationPermissionState.unavailable =>
        'This device or platform has no location service. Everything else '
            'still works.',
    };
  }

  Future<void> _requestPermission(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final next = await ref
          .read(locationPermissionProvider.notifier)
          .request();
      if (next == LocationPermissionState.granted) {
        await ref.read(locationStateProvider.notifier).reload();
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_permissionOutcome(next))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not ask for location: $e')),
      );
    }
  }

  Future<void> _openSystemSettings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(openAppSettingsProvider)();
    if (opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Opened system settings. Enable location, then come '
              'back and press "Get a fresh fix".'),
        ),
      );
    } else {
      // Being honest beats a button that silently does nothing.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This platform has no app-settings screen for '
              'FloodRelief. Turn location on in your system settings, then '
              'press "Get a fresh fix".'),
        ),
      );
    }
    await ref.read(locationPermissionProvider.notifier).refresh();
  }

  static String _permissionOutcome(LocationPermissionState state) =>
      switch (state) {
        LocationPermissionState.granted => 'Location allowed.',
        LocationPermissionState.denied => 'Location was declined.',
        LocationPermissionState.permanentlyDenied =>
          'Location is blocked in system settings and has to be enabled there.',
        LocationPermissionState.unavailable =>
          'This device has no location service.',
      };
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

class _StorageCard extends ConsumerWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.cleaning_services_outlined),
        title: const Text('Clear local data'),
        subtitle: const Text(
          'Deletes SOS records, relayed and queued packets, flood reports, '
          'help requests, alerts and contacts. Rescue teams, shelters, your '
          'device ID and every setting are kept.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _confirmClear(context, ref),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear local data?'),
        content: const Text(
          'This cannot be undone. Messages that have not been transmitted '
          'yet will be lost too.\n\n'
          'Shelters, rescue teams, your device ID and your settings stay on '
          'this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await ref.read(localDataServiceProvider).clearUserData();
      messenger.showSnackBar(SnackBar(content: Text(summary.describe())));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not clear local data: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

class _DiagnosticsCard extends ConsumerWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(errorLogProvider);
    final pending = ref.watch(pendingPacketCountProvider);
    final link = ref.watch(communicationStatusProvider).value;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Diagnostics',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DiagRow(
              label: 'Link state',
              value: link == null
                  ? 'not started'
                  : '${link.state.name} · ${link.detail}',
            ),
            pending.when(
              loading: () => const _DiagRow(label: 'Queued packets', value: '…'),
              error: (error, _) => _DiagRow(
                label: 'Queued packets',
                value: 'unavailable ($error)',
              ),
              data: (count) => _DiagRow(
                label: 'Queued packets',
                value: '$count waiting to transmit',
              ),
            ),
            _DiagRow(
              label: 'Recorded errors',
              value: log.isEmpty
                  ? 'none since launch'
                  : '${log.length} (keeps the newest ${log.capacity})',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: log.isEmpty
                      ? null
                      : () => showErrorLogDialog(context),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: Text(
                    log.isEmpty ? 'No errors to show' : 'View error log',
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    log.clear();
                    messenger(context, 'Error log cleared.');
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear log'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static void messenger(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demo mode
// ---------------------------------------------------------------------------

/// The simulated mesh only exists when the app was built with one. In a normal
/// production build [demoControllerProvider] is null, and this card says so
/// rather than showing a switch that cannot do anything.
class _DemoModeCard extends ConsumerWidget {
  const _DemoModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(demoControllerProvider);

    if (controller == null) {
      return const CapabilityNote(
        icon: Icons.science_outlined,
        text: 'The simulated relay mesh is not part of this build, so demo '
            'mode is unavailable. The app runs on the real Bluetooth '
            'transport, which needs two physical devices to pass traffic.',
      );
    }

    final demoMode = ref.watch(demoModeProvider);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            value: demoMode.value ?? false,
            onChanged: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(demoModeProvider.notifier).setEnabled(v);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Could not change demo mode: $e')),
                );
              }
            },
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Demo mode'),
            subtitle: const Text(
              'Runs a simulated relay mesh (A → B → C → rescue) inside this '
              'device so the full SOS workflow can be exercised without '
              'hardware.',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Open the demo panel'),
            subtitle: const Text('Trigger simulated SOSs and watch routing.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => AppNav.pushNamed(context, AppRoutes.demoPanel),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
