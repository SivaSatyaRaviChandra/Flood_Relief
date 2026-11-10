/// Help requests stored on this device, with the status transitions a rescue
/// operator can legally apply.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/utils/time_format.dart';
import '../../models/enums/help_category.dart';
import '../../models/help_request.dart';
import '../../services/help_request_service.dart';
import '../widgets/badges.dart';
import '../widgets/state_views.dart';

class HelpRequestsScreen extends ConsumerStatefulWidget {
  const HelpRequestsScreen({super.key, this.highlightRequestId});

  final String? highlightRequestId;

  @override
  ConsumerState<HelpRequestsScreen> createState() => _HelpRequestsScreenState();
}

class _HelpRequestsScreenState extends ConsumerState<HelpRequestsScreen> {
  bool _openOnly = false;

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(helpRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Request help',
            onPressed: () => AppNav.pushNamed(context, AppRoutes.requestHelp),
          ),
        ],
      ),
      body: requestsAsync.when(
        loading: () => const LoadingStateView(message: 'Reading local requests...'),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(helpRequestsProvider),
        ),
        data: (all) {
          final filtered = _openOnly
              ? all.where((r) => r.isOpen).toList()
              : all;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Open only'),
                      selected: _openOnly,
                      onSelected: (v) => setState(() => _openOnly = v),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${filtered.length} of ${all.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.volunteer_activism_outlined,
                        title: all.isEmpty
                            ? 'No help requests yet'
                            : 'No open requests',
                        message: all.isEmpty
                            ? 'Ask for food, water, medicine, transport or a '
                                'place to sleep. The request is saved on this '
                                'device immediately.'
                            : 'Every request has been handled or cancelled.',
                        action: all.isEmpty
                            ? FilledButton.icon(
                                onPressed: () => AppNav.pushNamed(
                                  context,
                                  AppRoutes.requestHelp,
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('Request help'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.refresh(helpRequestsProvider.future),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 32),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final request = filtered[index];
                            return HelpRequestTile(
                              request: request,
                              highlighted:
                                  request.requestId == widget.highlightRequestId,
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
}

/// One request row.
class HelpRequestTile extends StatelessWidget {
  const HelpRequestTile({
    super.key,
    required this.request,
    this.highlighted = false,
  });

  final HelpRequest request;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlighted ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(_icon(request.category), color: scheme.primary),
        ),
        title: Text(
          '${request.category.label} · ${request.peopleCount} '
          '${request.peopleCount == 1 ? 'person' : 'people'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HelpStatusChip(status: request.status),
                  _PriorityDot(priority: request.priority),
                  Text(
                    formatRelative(request.timestamp),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        onTap: () =>
            AppNav.pushHelpRequestDetails(context, request.requestId),
      ),
    );
  }

  static IconData _icon(HelpCategory category) => switch (category) {
        HelpCategory.rescue => Icons.personal_injury,
        HelpCategory.food => Icons.restaurant,
        HelpCategory.drinkingWater => Icons.water_drop,
        HelpCategory.medical => Icons.medical_services,
        HelpCategory.shelter => Icons.home_work,
        HelpCategory.transport => Icons.directions_car,
        HelpCategory.other => Icons.help_outline,
      };
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final HelpPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      HelpPriority.urgent => const Color(0xFFC62828),
      HelpPriority.high => const Color(0xFFEF6C00),
      HelpPriority.medium => const Color(0xFF1565C0),
      HelpPriority.low => const Color(0xFF2E7D32),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        priority.label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Detail screen for one request: the full record plus the legal transitions.
///
/// The id arrives through the route arguments (`AppNav.pushHelpRequestDetails`
/// or a plain `pushNamed`), so this screen is registered as a named route
/// without a closure. Pass [requestId] directly to open it outside the router.
class HelpRequestDetailsScreen extends ConsumerWidget {
  const HelpRequestDetailsScreen({super.key, this.requestId});

  /// Falls back to the route argument when the screen is opened by name.
  final String? requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    final id = requestId ?? (argument is String ? argument : null);
    final requests = ref.watch(helpRequestsProvider);
    final scheme = Theme.of(context).colorScheme;

    if (id == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Help request')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'No request selected',
          message: 'Open this screen from the help requests list.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Help request')),
      body: requests.when(
        loading: () => const LoadingStateView(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(helpRequestsProvider),
        ),
        data: (all) {
          final matches = all.where((r) => r.requestId == id);
          if (matches.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Request not found',
              message: 'It may have been deleted, or it was filed on another '
                  'device. This build does not sync requests between devices.',
            );
          }
          final request = matches.first;
          final allowed = allowedHelpTransitions(request.status);
          final user = ref.watch(currentUserProvider).value;
          final isOperator = user?.isRescue ?? false;

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SectionCard(
                title: request.category.label,
                subtitle: request.requestId,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        HelpStatusChip(status: request.status),
                        _PriorityDot(priority: request.priority),
                        HelpCategoryChip(category: request.category),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      request.description,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 14),
                    _Field(label: 'People', value: '${request.peopleCount}'),
                    _Field(
                      label: 'Filed',
                      value: formatFull(request.timestamp),
                    ),
                    if (request.statusUpdatedAt != null)
                      _Field(
                        label: 'Status last changed',
                        value: formatFull(request.statusUpdatedAt!),
                      ),
                    _Field(
                      label: 'Position',
                      value: '${request.latitude.toStringAsFixed(5)}, '
                          '${request.longitude.toStringAsFixed(5)}',
                    ),
                    if (request.accuracy != null)
                      _Field(
                        label: 'Accuracy',
                        value: '±${request.accuracy!.toStringAsFixed(0)} m',
                      ),
                    if (request.reporterName != null)
                      _Field(
                        label: 'Requested by',
                        value: request.reporterName!,
                      ),
                    if (request.assignedTeamId != null)
                      _Field(
                        label: 'Assigned team',
                        value: request.assignedTeamId!,
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: isOperator ? 'Operator actions' : 'Request progress',
                subtitle: isOperator
                    ? 'Only the transitions the lifecycle allows are offered.'
                    : 'These are set by a rescue operator on a device you can '
                        'see. This build has no server, so nothing changes '
                        'remotely.',
                child: allowed.isEmpty
                    ? Text(
                        'This request is ${request.status.label.toLowerCase()}; '
                        'no further changes are possible.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isOperator)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Sign in as a rescue operator on this device '
                                'to change the status.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final next in allowed)
                                OutlinedButton(
                                  onPressed: isOperator
                                      ? () => _apply(context, ref, id, next)
                                      : null,
                                  child: Text(_verb(next)),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
              SectionCard(
                title: 'Danger zone',
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDelete(context, ref, request),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete this request'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _verb(HelpRequestStatus status) => switch (status) {
        HelpRequestStatus.pending => 'Mark pending',
        HelpRequestStatus.acknowledged => 'Acknowledge',
        HelpRequestStatus.inProgress => 'Start work',
        HelpRequestStatus.fulfilled => 'Mark fulfilled',
        HelpRequestStatus.cancelled => 'Cancel',
      };

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    HelpRequestStatus next,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider).value;
    try {
      await ref.read(helpRequestServiceProvider).updateStatus(
            requestId,
            next,
            teamId: next == HelpRequestStatus.cancelled ? null : user?.teamId,
            clearTeam: next == HelpRequestStatus.cancelled,
          );
      messenger.showSnackBar(
        SnackBar(content: Text('Request is now ${next.label.toLowerCase()}.')),
      );
    } on InvalidHelpStatusTransition catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Not allowed: ${e.toString()}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update the request: $e')),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    HelpRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this request?'),
        content: Text(
          '${request.requestId} will be removed from this device. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(helpRequestServiceProvider).delete(request.requestId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Request deleted.')),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete the request: $e')),
      );
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

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
