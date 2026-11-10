/// A situation map of everything stored on this device.
///
/// Uses the app's own offline map widget: no tile server, no API key, no
/// network. It plots local SOSs, flood reports, help requests and shelters on
/// a projected grid, so it works with the radio off and the GPS unavailable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/time_format.dart';
import '../../models/enums/alert_severity.dart';
import '../../models/enums/flood_severity.dart';
import '../../models/enums/sos_priority.dart';
import '../../models/sos_request.dart';
import '../widgets/offline_map.dart';
import '../widgets/state_views.dart';

class SituationMapScreen extends ConsumerWidget {
  const SituationMapScreen({super.key});

  static const _layerFlags = <String, bool>{
    'SOS': true,
    'Flood reports': true,
    'Help requests': true,
    'Shelters': true,
    'Alerts': true,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sos = ref.watch(allSosProvider).value ?? const <SosRequest>[];
    final reports = ref.watch(floodReportsProvider).value ?? const [];
    final requests = ref.watch(helpRequestsProvider).value ?? const [];
    final shelters = ref.watch(sheltersProvider).value ?? const [];
    final alerts = ref.watch(alertsProvider).value ?? const [];
    final position = ref.watch(lastKnownPositionProvider);

    // Layer filtering lives in local mutable state keyed by the constant map
    // above; a StatefulWidget is the honest way to hold it.
    return _MapBody(
      sos: sos,
      reports: reports,
      requests: requests,
      shelters: shelters,
      alerts: alerts,
      position: position,
      layerFlags: _layerFlags,
    );
  }
}

class _MapBody extends StatefulWidget {
  const _MapBody({
    required this.sos,
    required this.reports,
    required this.requests,
    required this.shelters,
    required this.alerts,
    required this.position,
    required this.layerFlags,
  });

  final List<SosRequest> sos;
  final List<dynamic> reports;
  final List<dynamic> requests;
  final List<dynamic> shelters;
  final List<dynamic> alerts;
  final ({double lat, double lng})? position;
  final Map<String, bool> layerFlags;

  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> {
  late final Map<String, bool> _layers = Map.of(widget.layerFlags);

  @override
  Widget build(BuildContext context) {
    final markers = <MapMarker>[
      if (_layers['SOS'] ?? true)
        for (final s in widget.sos)
          if (s.status.isActive)
            MapMarker(
              id: s.sosId,
              label: s.sosId,
              subtitle: '${s.totalPeople} people',
              latitude: s.latitude,
              longitude: s.longitude,
              color: _sosColor(s.priority),
            ),
      if (_layers['Flood reports'] ?? true)
        for (final r in widget.reports)
          MapMarker(
            id: r.reportId,
            label: r.reportId,
            subtitle: r.severity.label,
            latitude: r.latitude,
            longitude: r.longitude,
            color: _severityColor(r.severity),
          ),
      if (_layers['Help requests'] ?? true)
        for (final r in widget.requests)
          if (r.isOpen)
            MapMarker(
              id: r.requestId,
              label: r.requestId,
              subtitle: r.category.label,
              latitude: r.latitude,
              longitude: r.longitude,
              color: const Color(0xFF6A1B9A),
            ),
      if (_layers['Shelters'] ?? true)
        for (final s in widget.shelters)
          if (s.hasCoordinates)
            MapMarker(
              id: s.shelterId,
              label: s.name,
              subtitle: s.capacity <= 0
                  ? '${s.occupied} inside'
                  : '${s.availableCapacity} free',
              latitude: s.latitude!,
              longitude: s.longitude!,
              color: const Color(0xFF2E7D32),
            ),
      if (_layers['Alerts'] ?? true)
        for (final a in widget.alerts)
          if (a.hasCoordinates)
            MapMarker(
              id: a.alertId,
              label: a.title,
              subtitle: a.severity.label,
              latitude: a.latitude!,
              longitude: a.longitude!,
              color: _alertColor(a.severity),
            ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Situation map'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final entry in _layers.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(entry.key),
                      selected: entry.value,
                      onSelected: (v) =>
                          setState(() => _layers[entry.key] = v),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const CapabilityNote(
            icon: Icons.map_outlined,
            text: 'Drawn from data stored on this device. There is no map '
                'server in this build, so the background is a projected grid '
                'rather than streets — every marker is at its real latitude '
                'and longitude.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OfflineMap(
              markers: markers,
              height: 320,
              center: widget.position == null
                  ? null
                  : (
                      latitude: widget.position!.lat,
                      longitude: widget.position!.lng,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              '${markers.length} marker${markers.length == 1 ? '' : 's'} shown',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (markers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: EmptyState(
                icon: Icons.map_outlined,
                title: 'Nothing to plot',
                message: 'Once an SOS, flood report, help request or shelter '
                    'with coordinates is stored on this device it appears '
                    'here. Enable a layer above to show its markers.',
              ),
            ),
          const SizedBox(height: 8),
          const _LegendCard(),
          if (widget.position == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'No position captured yet, so the map is centred on the marker '
                'centroid instead of on you.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Freshness: flood reports older than '
              '${Limits.floodReportFreshness.inHours} hours are still shown but '
              'no longer drive alerts. SOS markers disappear once resolved.',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.sos.isNotEmpty) _SosList(sos: widget.sos),
        ],
      ),
    );
  }

  static Color _sosColor(SosPriority priority) => switch (priority) {
        SosPriority.critical => const Color(0xFFC62828),
        SosPriority.high => const Color(0xFFEF6C00),
        SosPriority.medium => const Color(0xFF1565C0),
        SosPriority.low => const Color(0xFF2E7D32),
      };

  static Color _severityColor(FloodSeverity severity) => switch (severity) {
        FloodSeverity.low => const Color(0xFF558B2F),
        FloodSeverity.medium => const Color(0xFF9E9D24),
        FloodSeverity.high => const Color(0xFFEF6C00),
        FloodSeverity.critical => const Color(0xFFC62828),
      };

  static Color _alertColor(AlertSeverity severity) => switch (severity) {
        AlertSeverity.info => const Color(0xFF29B6F6),
        AlertSeverity.warning => const Color(0xFFFFA000),
        AlertSeverity.danger => const Color(0xFFF4511E),
        AlertSeverity.critical => const Color(0xFFB71C1C),
      };
}

class _LegendCard extends StatelessWidget {
  const _LegendCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Legend',
      child: Column(
        children: const [
          _LegendRow(color: Color(0xFFC62828), label: 'Critical SOS / critical flooding'),
          _LegendRow(color: Color(0xFFEF6C00), label: 'High priority SOS or flooding'),
          _LegendRow(color: Color(0xFF1565C0), label: 'Medium priority SOS'),
          _LegendRow(color: Color(0xFF6A1B9A), label: 'Open help request'),
          _LegendRow(color: Color(0xFF2E7D32), label: 'Shelter'),
          _LegendRow(color: Color(0xFFFFA000), label: 'Warning alert'),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// A compact SOS list under the map so a marker is not the only way to reach a
/// record.
class _SosList extends StatelessWidget {
  const _SosList({required this.sos});

  final List<SosRequest> sos;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'SOS on this device',
      child: Column(
        children: [
          for (final s in sos.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.sosId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '${s.totalPeople} people',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatRelative(s.timestamp),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (sos.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+${sos.length - 10} more',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
