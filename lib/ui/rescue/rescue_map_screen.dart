/// Offline map of every SOS and every rescue team.
///
/// Marker colour encodes risk: critical/high SOSs are red/orange, teams are
/// green. No tile service — the custom OfflineMap renders a local projection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../models/enums/sos_priority.dart';
import '../widgets/offline_map.dart';

class RescueMapScreen extends ConsumerWidget {
  const RescueMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allSosProvider).value ?? const [];
    final teams = ref.watch(teamsProvider).value ?? const [];

    final sosMarkers = [
      for (final sos in all)
        MapMarker(
          id: sos.sosId,
          label: sos.sosId,
          subtitle: sos.status.label,
          latitude: sos.latitude,
          longitude: sos.longitude,
          color: _sosColor(sos.priority),
        ),
    ];
    final teamMarkers = [
      for (final team in teams)
        if (team.latitude != null && team.longitude != null)
          MapMarker(
            id: team.teamId,
            label: team.teamName,
            subtitle: 'Team · ${team.status.label}',
            latitude: team.latitude!,
            longitude: team.longitude!,
            color: const Color(0xFF2E7D32),
          ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Situation map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'List view',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: OfflineMap(
                height: double.infinity,
                markers: [...sosMarkers, ...teamMarkers],
              ),
            ),
          ),
          const _Legend(),
        ],
      ),
    );
  }

  static Color _sosColor(SosPriority p) => switch (p) {
        SosPriority.critical => const Color(0xFFC62828),
        SosPriority.high => const Color(0xFFEF6C00),
        SosPriority.medium => const Color(0xFF1565C0),
        SosPriority.low => const Color(0xFF2E7D32),
      };
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _dot('Critical', const Color(0xFFC62828)),
            _dot('High', const Color(0xFFEF6C00)),
            _dot('Medium', const Color(0xFF1565C0)),
            _dot('Low', const Color(0xFF2E7D32)),
            _dot('Rescue team', const Color(0xFF2E7D32), ring: true),
          ],
        ),
      ),
    );
  }

  Widget _dot(String label, Color color, {bool ring = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: ring ? null : color,
            shape: BoxShape.circle,
            border: ring ? Border.all(color: color, width: 3) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}