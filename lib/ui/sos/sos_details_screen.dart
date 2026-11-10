/// SOS details: full record, priority rationale, status timeline, and role
/// aware actions (rescue operators can acknowledge/assign/start/resolve).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/time_format.dart';
import '../../models/enums/sos_status.dart';
import '../../models/rescue_team.dart';
import '../../models/sos_request.dart';
import '../../services/sos_service.dart';
import '../widgets/badges.dart';
import '../widgets/offline_map.dart';

class SosDetailsScreen extends ConsumerWidget {
  const SosDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosId = ModalRoute.of(context)!.settings.arguments as String?;
    final requestAsync = ref.watch(sosByIdProvider(sosId ?? ''));
    final user = ref.watch(currentUserProvider).value;
    final isRescue = user?.isRescue ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Demo panel',
            onPressed: () => AppNav.pushNamed(context, AppRoutes.demoPanel),
          ),
        ],
      ),
      body: requestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load SOS: $e')),
        data: (request) {
          if (request == null) {
            return const Center(child: Text('SOS not found on this device.'));
          }
          return _DetailsBody(
            request: request,
            isRescue: isRescue,
            operatorTeamId: user?.teamId,
          );
        },
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({
    required this.request,
    required this.isRescue,
    this.operatorTeamId,
  });

  final SosRequest request;
  final bool isRescue;

  /// The signed-in operator's team, so the audit trail names the real team
  /// instead of a hard-coded placeholder.
  final String? operatorTeamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final verdict = ref.read(priorityServiceProvider).evaluate(
          emergencyType: request.emergencyType,
          people: request.people,
          description: request.description,
        );
    final teamsAsync = ref.watch(teamsProvider);
    final teams = teamsAsync.value ?? const <RescueTeam>[];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SizedBox(
          height: 190,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OfflineMap(
              markers: [
                MapMarker(
                  id: request.sosId,
                  label: request.sosId,
                  latitude: request.latitude,
                  longitude: request.longitude,
                  color: kDangerColor,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  request.sosId,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              StatusChip(status: request.status),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              PriorityBadge(priority: request.priority),
              const SizedBox(width: 8),
              if (request.acknowledged)
                const Chip(
                  avatar: Icon(Icons.check_circle, size: 18, color: Color(0xFF2E7D32)),
                  label: Text('ACK received'),
                  visualDensity: VisualDensity.compact,
                )
              else
                const Chip(
                  avatar: Icon(Icons.hourglass_empty, size: 18, color: Colors.orange),
                  label: Text('Not yet acknowledged'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(context, 'Emergency', request.emergencyType.label),
              _row(context, 'People', '${request.totalPeople} affected'),
              if (request.people.childrenCount > 0)
                _row(context, 'Children', '${request.people.childrenCount}'),
              if (request.people.elderlyCount > 0)
                _row(context, 'Elderly', '${request.people.elderlyCount}'),
              if (request.people.pregnantWomenCount > 0)
                _row(context, 'Pregnant women', '${request.people.pregnantWomenCount}'),
              if (request.people.specialAssistanceCount > 0)
                _row(context, 'Special assistance', '${request.people.specialAssistanceCount}'),
              _row(context, 'Coordinates',
                  '${request.latitude.toStringAsFixed(5)}, ${request.longitude.toStringAsFixed(5)}'),
              _row(context, 'Saved', formatFull(request.timestamp)),
              _row(context, 'From device', request.originDeviceId),
              _row(context, 'Hops travelled', '${request.hopCount}'),
              if (request.assignedTeamId != null)
                _row(context, 'Assigned team', request.assignedTeamId!),
              if (request.description.isNotEmpty) ...[
                const Divider(height: 20),
                const Text('Description',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(request.description),
              ],
            ],
          ),
        ),
        _Section(
          title: 'Why this priority',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reason in verdict.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $reason',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        _Section(
          title: 'Status history',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in request.statusHistory)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.previousStatus?.label ?? '—'} → '
                              '${entry.newStatus.label}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${formatFull(entry.timestamp)}'
                              '${entry.teamId != null ? ' · ${entry.teamId}' : ''}'
                              '${entry.note != null ? ' · ${entry.note}' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (isRescue) ...[
          const SizedBox(height: 8),
          _RescueActions(
            request: request,
            teams: teams,
            teamsLoading: teamsAsync.isLoading,
            operatorTeamId: operatorTeamId,
          ),
        ] else ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(networkingProvider)
                    .start(requestPermissions: true);
              },
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Search for relay / rescue now'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _RescueActions extends ConsumerWidget {
  const _RescueActions({
    required this.request,
    required this.teams,
    required this.teamsLoading,
    this.operatorTeamId,
  });

  final SosRequest request;
  final List<RescueTeam> teams;

  /// The signed-in operator's team. Used as the actor/team for acknowledgement,
  /// start and resolve, and as the fallback when assigning.
  final String? operatorTeamId;

  /// True while the team list has not produced its first value yet. The
  /// assign action stays visible (disabled) instead of silently disappearing,
  /// so an operator is never left guessing why assignment is unavailable.
  final bool teamsLoading;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status updated.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      final message = e is AppError
          ? e.message
          : e is InvalidStatusTransitionError
              ? 'Not allowed: ${e.from} → ${e.to}'
              : 'Action failed: ${e.runtimeType}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosService = ref.read(sosServiceProvider);
    final status = request.status;
    final scheme = Theme.of(context).colorScheme;

    // Audit entries should name the real signed-in team. The fallback keeps
    // older flows (and tests) working when a team was never selected.
    final actorId = operatorTeamId ?? 'RESCUE-OPS';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rescue actions',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (status.canTransitionTo(SosStatus.acknowledged))
            OutlinedButton.icon(
              onPressed: () => _run(context, ref, () => sosService
                  .acknowledgeSos(request.sosId, teamId: actorId)),
              icon: const Icon(Icons.thumb_up_alt_outlined),
              label: const Text('Acknowledge'),
            ),
          if (status.canTransitionTo(SosStatus.rescueAssigned)) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: teams.isEmpty
                  ? null
                  : () => _pickTeam(context, ref, sosService),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Assign rescue team'),
            ),
            if (teams.isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                teamsLoading
                    ? 'Loading rescue teams…'
                    : 'No rescue teams are registered on this device yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
          if (status.canTransitionTo(SosStatus.inProgress)) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _run(context, ref,
                  () => sosService.startRescue(request.sosId,
                      actorId: actorId, teamId: operatorTeamId)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start rescue'),
            ),
          ],
          if (status.canTransitionTo(SosStatus.resolved)) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _run(context, ref,
                  () => sosService.markResolved(request.sosId,
                      actorId: actorId, teamId: operatorTeamId)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.task_alt),
              label: const Text('Mark resolved'),
            ),
          ],
          if (!status.canTransitionTo(SosStatus.acknowledged) &&
              !status.canTransitionTo(SosStatus.rescueAssigned) &&
              !status.canTransitionTo(SosStatus.inProgress) &&
              !status.canTransitionTo(SosStatus.resolved))
            const Text(
              'No further actions available for this status.',
              style: TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Future<void> _pickTeam(
    BuildContext context,
    WidgetRef ref,
    SosService sosService,
  ) async {
    final selected = await showModalBottomSheet<RescueTeam>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Assign a rescue team',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final team in teams)
              ListTile(
                leading: const Icon(Icons.directions_boat),
                title: Text(team.teamName),
                subtitle: Text('${team.teamLeader} · ${team.status.label}'),
                onTap: () => Navigator.of(context).pop(team),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (!context.mounted) return;
    await _run(context, ref, () => sosService.assignTeam(
          request.sosId,
          selected.teamId,
          actorId: operatorTeamId ?? 'RESCUE-OPS',
        ));
  }
}