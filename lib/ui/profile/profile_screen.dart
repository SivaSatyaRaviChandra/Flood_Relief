/// The signed-in user's profile: identity, this device's data footprint, and
/// the way out (switch role / sign out).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/utils/time_format.dart';
import '../../services/local_data_service.dart';
import '../widgets/state_views.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final deviceId = ref.watch(deviceIdProvider);
    final usage = ref.watch(_localUsageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: user == null
          ? EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Not signed in',
              message: 'Register on this device to send SOSs or operate a '
                  'rescue team.',
              action: FilledButton.icon(
                onPressed: () =>
                    AppNav.replaceAll(context, AppRoutes.onboarding),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Register'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SectionCard(
                  title: user.displayName,
                  subtitle: user.userId,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            user.isRescue
                                ? Icons.health_and_safety
                                : Icons.person_pin_circle,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            user.role.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      if (user.phone != null) ...[
                        const SizedBox(height: 10),
                        Text('Phone: ${user.phone}'),
                      ],
                      if (user.teamId != null) ...[
                        const SizedBox(height: 6),
                        Text('Team: ${user.teamId}'),
                      ],
                      if (user.createdAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Registered ${formatFull(user.createdAt!)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const CapabilityNote(
                  icon: Icons.badge_outlined,
                  text: 'This build has no account server. Your profile is a '
                      'row in a local database — it identifies you to other '
                      'nodes on the mesh and is never sent anywhere else.',
                ),
                SectionCard(
                  title: 'This device',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Row(label: 'Device ID', value: deviceId),
                      const _Row(
                        label: 'Storage',
                        value: 'Local only (Hive), no cloud sync',
                      ),
                      const _Row(
                        label: 'Network',
                        value: 'Bluetooth mesh, no internet needed',
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Stored on this device',
                  subtitle: 'Cleared from Settings → Clear local data.',
                  child: usage.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) => Text('Could not read storage: $error'),
                    data: (summary) => Column(
                      children: [
                        _Row(label: 'SOS records', value: '${summary.sosRecords}'),
                        _Row(
                          label: 'Flood reports',
                          value: '${summary.floodReports}',
                        ),
                        _Row(
                          label: 'Help requests',
                          value: '${summary.helpRequests}',
                        ),
                        _Row(
                          label: 'Shelters',
                          value: '${summary.shelters}',
                        ),
                        _Row(label: 'Contacts', value: '${summary.contacts}'),
                        _Row(label: 'Alerts', value: '${summary.alerts}'),
                        _Row(
                          label: 'Packets queued to send',
                          value: '${summary.queuedPackets}',
                        ),
                      ],
                    ),
                  ),
                ),
                SectionCard(
                  title: 'Jump to',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.mySos),
                        icon: const Icon(Icons.sos, size: 18),
                        label: const Text('My SOSs'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.floodReports),
                        icon: const Icon(Icons.water_drop_outlined, size: 18),
                        label: const Text('Flood reports'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.helpRequests),
                        icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                        label: const Text('Help requests'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.shelters),
                        icon: const Icon(Icons.home_work_outlined, size: 18),
                        label: const Text('Shelters'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.contacts),
                        icon: const Icon(Icons.contact_phone_outlined, size: 18),
                        label: const Text('Contacts'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.alerts),
                        icon: const Icon(Icons.notifications_outlined, size: 18),
                        label: const Text('Alerts'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppNav.pushNamed(context, AppRoutes.settings),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('Settings'),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Account',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _switchRole(context),
                        icon: const Icon(Icons.swap_horiz),
                        label: Text(user.isRescue
                            ? 'Switch to an affected person'
                            : 'Switch to a rescue operator'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _signOut(context, ref),
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out on this device'),
                      ),
                    ],
                  ),
                ),
                const _RoleLegend(),
              ],
            ),
    );
  }

  Future<void> _switchRole(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch role?'),
        content: const Text(
          'You will go back to the registration screen. Your SOS records, '
          'reports and shelters stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      AppNav.replaceAll(context, AppRoutes.onboarding);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your profile is removed from this device. Stored SOSs, reports, '
          'shelters and contacts are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(currentUserProvider.notifier).signOut();
    if (context.mounted) AppNav.replaceAll(context, AppRoutes.onboarding);
  }
}

/// The storage snapshot shown on the profile screen.
final _localUsageProvider = FutureProvider<StorageUsage>((ref) {
  return ref.read(localDataServiceProvider).currentUsage();
});

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

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
            width: 170,
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

/// A small legend so the "switch to rescue operator" button is not a mystery.
class _RoleLegend extends StatelessWidget {
  const _RoleLegend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        'An affected person sends SOSs and reports conditions. A rescue '
        'operator joins a team and takes SOSs through to resolved.',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
