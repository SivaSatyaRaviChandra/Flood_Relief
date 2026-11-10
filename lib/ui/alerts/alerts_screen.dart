/// The alert feed.
///
/// Alerts here are never invented. Every entry is *derived* from data that
/// really exists on this device (an SOS that changed status, a critical flood
/// report, an urgent help request, a shelter that filled up) or written by a
/// rescue operator as an advisory. See `services/alert_service.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/time_format.dart';
import '../../models/alert_record.dart';
import '../../models/enums/alert_severity.dart';
import '../widgets/badges.dart';
import '../widgets/state_views.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsProvider);
    // Watching this keeps the feed re-derived when the underlying data
    // changes; `refresh` is idempotent so nothing is duplicated.
    ref.watch(alertFeedRefresherProvider);
    final user = ref.watch(currentUserProvider).value;
    final isOperator = user?.isRescue ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-derive alerts',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final created = await ref
                  .read(alertFeedRefresherProvider.notifier)
                  .refreshNow();
              final failure = ref.read(alertFeedRefresherProvider.notifier)
                  .lastFailure;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    failure != null
                        ? 'Could not refresh alerts: $failure'
                        : created == 0
                            ? 'Alerts are up to date.'
                            : 'Added $created new alert${created == 1 ? '' : 's'}.',
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.mark_email_read_outlined),
            tooltip: 'Mark all as read',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final n = await ref.read(alertServiceProvider).markAllRead();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(n == 0
                        ? 'No unread alerts.'
                        : 'Marked $n alert${n == 1 ? '' : 's'} as read.'),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Could not mark alerts as read: $e')),
                );
              }
            },
          ),
          if (isOperator)
            IconButton(
              icon: const Icon(Icons.campaign_outlined),
              tooltip: 'Publish an advisory',
              onPressed: () => _publishAdvisory(context, ref),
            ),
        ],
      ),
      body: alertsAsync.when(
        loading: () => const LoadingStateView(message: 'Deriving alerts...'),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(alertsProvider),
        ),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'No alerts',
              message: 'Alerts appear when an SOS changes status, a critical '
                  'flood report is filed, an urgent help request is raised, '
                  'or a shelter fills up — all on this device.',
            );
          }
          final unread = alerts.where((a) => !a.read).length;
          return RefreshIndicator(
            onRefresh: () async {
              // The feed is a stream, so re-deriving is enough — the
              // repository emits and `alertsProvider` follows.
              await ref.read(alertFeedRefresherProvider.notifier).refreshNow();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  child: Text(
                    unread == 0
                        ? 'All ${alerts.length} alerts read.'
                        : '$unread unread of ${alerts.length}.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final alert in alerts) _AlertTile(alert: alert),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _publishAdvisory(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AdvisoryForm(),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final color = alertSeverityColor(alert.severity);
    return Card(
      color: alert.read ? null : color.withValues(alpha: 0.06),
      child: ListTile(
        leading: Icon(
          switch (alert.severity) {
            AlertSeverity.critical => Icons.report_gmailerrorred,
            AlertSeverity.danger => Icons.error_outline,
            AlertSeverity.warning => Icons.warning_amber_rounded,
            AlertSeverity.info => Icons.info_outline,
          },
          color: color,
        ),
        title: Text(
          alert.title,
          style: TextStyle(
            fontWeight: alert.read ? FontWeight.w500 : FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.description, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AlertSeverityChip(severity: alert.severity),
                  Text(
                    alert.source.label,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  Text(
                    formatRelative(alert.timestamp),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                  if (alert.locationLabel != null)
                    Text(
                      alert.locationLabel!,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing: alert.read
            ? null
            : IconButton(
                icon: const Icon(Icons.done),
                tooltip: 'Mark as read',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(alertServiceProvider).markRead(alert.alertId);
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Could not mark as read: $e')),
                    );
                  }
                },
              ),
      ),
    );
  }
}

class _AdvisoryForm extends ConsumerStatefulWidget {
  const _AdvisoryForm();

  @override
  ConsumerState<_AdvisoryForm> createState() => _AdvisoryFormState();
}

class _AdvisoryFormState extends ConsumerState<_AdvisoryForm> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  AlertSeverity _severity = AlertSeverity.warning;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty ||
        _bodyController.text.trim().isEmpty) {
      setState(() => _error = 'A title and a description are both required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(alertServiceProvider).publishAdvisory(
            title: _titleController.text,
            description: _bodyController.text,
            severity: _severity,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not publish: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Publish an advisory',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Saved on this device and shown in the alert feed of anyone who '
              'opens this build. It is not transmitted over the mesh.',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What should people do?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final s in AlertSeverity.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _severity == s,
                    onSelected: (_) => setState(() => _severity = s),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign),
              label: Text(_saving ? 'Publishing...' : 'Publish'),
            ),
          ],
        ),
      ),
    );
  }
}
