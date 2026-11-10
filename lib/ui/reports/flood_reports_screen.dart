/// The flood reports stored on this device, newest first.
///
/// Filters are applied against the *stored* data only; nothing here is fetched
/// from a network, because this build has no backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/time_format.dart';
import '../../models/enums/flood_severity.dart';
import '../../models/flood_report.dart';
import '../widgets/badges.dart';
import '../widgets/state_views.dart';

class FloodReportsScreen extends ConsumerStatefulWidget {
  const FloodReportsScreen({super.key, this.highlightReportId});

  /// When the screen is opened right after filing, the new report is brought
  /// into view and marked.
  final String? highlightReportId;

  @override
  ConsumerState<FloodReportsScreen> createState() => _FloodReportsScreenState();
}

class _FloodReportsScreenState extends ConsumerState<FloodReportsScreen> {
  bool _mineOnly = false;
  bool _freshOnly = false;

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(floodReportsProvider);
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flood reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Report flooding',
            onPressed: () => AppNav.pushNamed(context, AppRoutes.reportFlood),
          ),
        ],
      ),
      body: reportsAsync.when(
        loading: () => const LoadingStateView(message: 'Reading local reports...'),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(floodReportsProvider),
        ),
        data: (all) {
          final filtered = _filter(all);
          return Column(
            children: [
              _FilterBar(
                mineOnly: _mineOnly,
                freshOnly: _freshOnly,
                canFilterMine: user != null,
                onMineChanged: (v) => setState(() => _mineOnly = v),
                onFreshChanged: (v) => setState(() => _freshOnly = v),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.water_drop_outlined,
                        title: all.isEmpty
                            ? 'No flood reports yet'
                            : 'No reports match these filters',
                        message: all.isEmpty
                            ? 'Report what the water is doing where you are. '
                                'The report is saved on this device '
                                'immediately.'
                            : 'Turn off a filter to see the other reports.',
                        action: all.isEmpty
                            ? FilledButton.icon(
                                onPressed: () => AppNav.pushNamed(
                                  context,
                                  AppRoutes.reportFlood,
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('Report flooding'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: () async => ref.refresh(floodReportsProvider.future),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 32),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final report = filtered[index];
                            return FloodReportTile(
                              report: report,
                              highlighted:
                                  report.reportId == widget.highlightReportId,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<FloodReport> _filter(List<FloodReport> all) {
    final user = ref.read(currentUserProvider).value;
    final cutoff = DateTime.now().toUtc().subtract(Limits.floodReportFreshness);
    return all.where((r) {
      if (_mineOnly && user != null && r.reporterId != user.userId) return false;
      if (_freshOnly && r.timestamp.isBefore(cutoff)) return false;
      return true;
    }).toList();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.mineOnly,
    required this.freshOnly,
    required this.canFilterMine,
    required this.onMineChanged,
    required this.onFreshChanged,
  });

  final bool mineOnly;
  final bool freshOnly;
  final bool canFilterMine;
  final ValueChanged<bool> onMineChanged;
  final ValueChanged<bool> onFreshChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          if (canFilterMine)
            FilterChip(
              label: const Text('Mine'),
              selected: mineOnly,
              onSelected: onMineChanged,
            ),
          if (canFilterMine) const SizedBox(width: 8),
          FilterChip(
            label: Text('Last ${Limits.floodReportFreshness.inHours}h'),
            selected: freshOnly,
            onSelected: onFreshChanged,
          ),
        ],
      ),
    );
  }
}

/// One report row. Also used by the situation map's legend list.
class FloodReportTile extends ConsumerWidget {
  const FloodReportTile({
    super.key,
    required this.report,
    this.highlighted = false,
  });

  final FloodReport report;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlighted ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              severityColor(report.severity).withValues(alpha: 0.15),
          child: Icon(
            report.severity == FloodSeverity.critical
                ? Icons.priority_high
                : Icons.water_drop,
            color: severityColor(report.severity),
          ),
        ),
        title: Text(
          report.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FloodSeverityChip(severity: report.severity),
              WaterDepthChip(depth: report.waterDepth),
              if (report.affectedPeople > 0)
                Text(
                  '${report.affectedPeople} people',
                  style: const TextStyle(fontSize: 12),
                ),
              if (report.verified)
                const Chip(
                  label: Text('Confirmed'),
                  visualDensity: VisualDensity.compact,
                ),
              Text(
                formatRelative(report.timestamp),
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        onTap: () => _showDetail(context, ref),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.reportId,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FloodSeverityChip(severity: report.severity),
                  WaterDepthChip(depth: report.waterDepth),
                ],
              ),
              const SizedBox(height: 14),
              Text(report.description),
              const SizedBox(height: 14),
              _DetailRow(
                label: 'Reported',
                value: formatFull(report.timestamp),
              ),
              _DetailRow(
                label: 'Position',
                value: '${report.latitude.toStringAsFixed(5)}, '
                    '${report.longitude.toStringAsFixed(5)}',
              ),
              if (report.accuracy != null)
                _DetailRow(
                  label: 'Accuracy',
                  value: '±${report.accuracy!.toStringAsFixed(0)} m',
                ),
              _DetailRow(
                label: 'People affected',
                value: '${report.affectedPeople}',
              ),
              if (report.reporterName != null)
                _DetailRow(label: 'Reported by', value: report.reporterName!),
              _DetailRow(
                label: 'Confirmed by a rescue operator',
                value: report.verified ? 'Yes' : 'Not yet',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        try {
                          await ref
                              .read(floodReportServiceProvider)
                              .verify(report.reportId);
                          messenger.showSnackBar(const SnackBar(
                            content: Text('Report marked as confirmed.'),
                          ));
                          navigator.pop();
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Could not confirm: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(report.verified ? 'Confirmed' : 'Confirm'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        try {
                          await ref
                              .read(floodReportServiceProvider)
                              .delete(report.reportId);
                          messenger.showSnackBar(const SnackBar(
                            content: Text('Report deleted.'),
                          ));
                          navigator.pop();
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Could not delete: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

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
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}
