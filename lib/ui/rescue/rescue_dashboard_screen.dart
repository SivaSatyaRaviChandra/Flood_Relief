/// Rescue dashboard: all SOSs with status & priority filters, sorting, map
/// access, and team glance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../models/enums/sos_priority.dart';
import '../../models/enums/sos_status.dart';
import '../../models/sos_request.dart';
import '../widgets/badges.dart';
import '../widgets/sos_card.dart';

enum _Filter { all, active, myTeam, pending, acknowledged, inProgress }

enum _Sort { newest, priority }

class RescueDashboardScreen extends ConsumerStatefulWidget {
  const RescueDashboardScreen({super.key});

  @override
  ConsumerState<RescueDashboardScreen> createState() =>
      _RescueDashboardScreenState();
}

class _RescueDashboardScreenState
    extends ConsumerState<RescueDashboardScreen> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;

  List<SosRequest> _apply(List<SosRequest> all, {String? myTeamId}) {
    var list = switch (_filter) {
      _Filter.all => [...all],
      _Filter.active => all.where((s) => s.status.isActive).toList(),
      _Filter.myTeam => all
          .where((s) => myTeamId != null && s.assignedTeamId == myTeamId)
          .toList(),
      _Filter.pending => all
          .where((s) => s.status == SosStatus.pending)
          .toList(),
      _Filter.acknowledged => all
          .where((s) =>
              s.status == SosStatus.acknowledged ||
              s.status == SosStatus.rescueAssigned)
          .toList(),
      _Filter.inProgress => all
          .where((s) => s.status == SosStatus.inProgress)
          .toList(),
    };
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      case _Sort.priority:
        list.sort((a, b) {
          final byScore = _priorityOrder(b.priority)
              .compareTo(_priorityOrder(a.priority));
          return byScore != 0
              ? byScore
              : b.timestamp.compareTo(a.timestamp);
        });
    }
    return list;
  }

  static int _priorityOrder(SosPriority p) => switch (p) {
        SosPriority.critical => 4,
        SosPriority.high => 3,
        SosPriority.medium => 2,
        SosPriority.low => 1,
      };

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allSosProvider);
    final user = ref.watch(currentUserProvider).value;
    final teams = ref.watch(teamsProvider).value ?? const [];

    final sosList = _apply(allAsync.value ?? const [], myTeamId: user?.teamId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Rescue · ${user?.displayName ?? 'Dashboard'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Rescue teams',
            onPressed: () => AppNav.pushNamed(context, AppRoutes.rescueTeams),
          ),
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
      body: Column(
        children: [
          // Filter chips.
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in _Filter.values)
                  if (f != _Filter.myTeam || user?.teamId != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(f.label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${sosList.length} SOS records',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                DropdownButton<_Sort>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(
                      value: _Sort.newest,
                      child: Text('Newest first'),
                    ),
                    DropdownMenuItem(
                      value: _Sort.priority,
                      child: Text('Highest priority'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _sort = v ?? _Sort.newest),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  tooltip: 'Map view',
                  onPressed: () => AppNav.pushNamed(context, AppRoutes.rescueMap),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Team glance strip.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final team in teams.take(5))
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      children: [
                        TeamStatusChip(status: team.status),
                        const SizedBox(width: 6),
                        Text(
                          team.teamName,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // List.
          Expanded(
            child: allAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load SOSs: $e')),
              data: (_) {
                if (sosList.isEmpty) {
                  return const Center(
                    child: Text('No SOS records in this view.'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.refresh(allSosProvider.future),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: sosList.length,
                    itemBuilder: (context, index) {
                      final sos = sosList[index];
                      return SosCard(
                        request: sos,
                        onTap: () =>
                            AppNav.pushSosDetails(context, sos.sosId),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.active => 'Active',
        _Filter.myTeam => 'My team',
        _Filter.pending => 'Pending',
        _Filter.acknowledged => 'Acknowledged',
        _Filter.inProgress => 'In progress',
      };
}