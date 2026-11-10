/// Rescue operator sign-in: pick the team you are operating with.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../models/app_user.dart';
import '../../models/rescue_team.dart';

class RescueLoginScreen extends ConsumerStatefulWidget {
  const RescueLoginScreen({super.key});

  @override
  ConsumerState<RescueLoginScreen> createState() => _RescueLoginScreenState();
}

class _RescueLoginScreenState extends ConsumerState<RescueLoginScreen> {
  final _nameController = TextEditingController();
  RescueTeam? _team;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    final team = _team;
    if (team == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select your rescue team first.')),
      );
      return;
    }
    setState(() => _saving = true);
    final deviceId = ref.read(deviceIdProvider);
    final suffix = deviceId.replaceFirst('DEVICE-', '');
    final user = AppUser(
      userId: 'RESCUE-$suffix',
      displayName: _nameController.text.trim().isEmpty
          ? 'Operator (${team.teamId})'
          : _nameController.text.trim(),
      role: UserRole.rescue,
      phone: null,
      teamId: team.teamId,
      createdAt: DateTime.now().toUtc(),
    );
    await ref.read(currentUserProvider.notifier).signIn(user);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.rescueDashboard,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Rescue operator login')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.health_and_safety, size: 64, color: const Color(0xFF2E7D32)),
          const SizedBox(height: 12),
          Text(
            'Join the rescue dashboard',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Demo credentials: pick a team. There is no auth server in this '
            'offline build — the selected team is stored on this device.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Operator name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Your team',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          teams.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not load teams: $e'),
            data: (list) => list.isEmpty
                ? Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.groups_outlined, size: 36),
                          const SizedBox(height: 8),
                          const Text(
                            'No rescue teams are registered on this device yet. '
                            'Register your team first, then come back to sign in.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => AppNav.pushNamed(
                              context,
                              AppRoutes.rescueTeams,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Register a rescue team'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RadioGroup<RescueTeam>(
                    groupValue: _team,
                    onChanged: (t) => setState(() => _team = t),
                    child: Column(
                      children: [
                        for (final team in list)
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: RadioListTile<RescueTeam>(
                              value: team,
                              title: Text(team.teamName),
                              subtitle: Text(
                                  '${team.teamLeader} · ${team.status.label}'),
                              secondary: Icon(Icons.directions_boat,
                                  color: _team?.teamId == team.teamId
                                      ? scheme.primary
                                      : scheme.outlineVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _enter,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.dashboard_outlined),
            label: const Text('Open rescue dashboard'),
          ),
        ],
      ),
    );
  }
}