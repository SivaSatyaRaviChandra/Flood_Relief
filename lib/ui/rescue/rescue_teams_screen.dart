/// Rescue team registry.
///
/// Teams are stored on the device that registers them. This screen is where an
/// operator adds a team, edits its contact/base details and keeps its
/// availability status current — without it, a fresh install has no team to
/// sign in as and assignment has nothing to select.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../models/enums/team_status.dart';
import '../../models/rescue_team.dart';
import '../widgets/badges.dart';
import '../widgets/state_views.dart';

class RescueTeamsScreen extends ConsumerWidget {
  const RescueTeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescue teams'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add a rescue team',
            onPressed: () => _openForm(context, null),
          ),
        ],
      ),
      body: teamsAsync.when(
        loading: () => const LoadingStateView(message: 'Reading rescue teams...'),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(teamsProvider),
        ),
        data: (teams) {
          if (teams.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'No rescue teams registered',
              message: 'Add the teams operating in your area. Operators pick '
                  'their team when they sign in, and incidents can only be '
                  'assigned to a registered team.',
              action: FilledButton.icon(
                onPressed: () => _openForm(context, null),
                icon: const Icon(Icons.add),
                label: const Text('Add a rescue team'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(teamsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: teams.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '${teams.length} team${teams.length == 1 ? '' : 's'} on '
                      'this device',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return _TeamTile(team: teams[index - 1]);
              },
            ),
          );
        },
      ),
    );
  }

  static Future<void> _openForm(BuildContext context, RescueTeam? team) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TeamForm(initial: team),
    );
  }
}

class _TeamTile extends ConsumerWidget {
  const _TeamTile({required this.team});

  final RescueTeam team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: const Icon(Icons.directions_boat),
        ),
        title: Text(
          team.teamName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TeamStatusChip(status: team.status),
              Text('${team.teamLeader} · ${team.contact}',
                  style: const TextStyle(fontSize: 12)),
              if (team.baseLocation != null)
                Text(team.baseLocation!, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Team actions',
          onSelected: (value) {
            if (value == 'edit') {
              RescueTeamsScreen._openForm(context, team);
              return;
            }
            _setStatus(context, ref, value);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit team')),
            const PopupMenuDivider(),
            for (final status in TeamStatus.values)
              CheckedPopupMenuItem(
                value: status.code,
                checked: team.status == status,
                child: Text(status.label),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    String code,
  ) async {
    final status = TeamStatus.fromCode(code);
    if (status == null || status == team.status) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(rescueTeamServiceProvider)
          .setStatus(team.teamId, status);
      messenger.showSnackBar(
        SnackBar(content: Text('${team.teamName} is now ${status.label}.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update the team: $e')),
      );
    }
  }
}

class _TeamForm extends ConsumerStatefulWidget {
  const _TeamForm({this.initial});

  final RescueTeam? initial;

  @override
  ConsumerState<_TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends ConsumerState<_TeamForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _leader;
  late final TextEditingController _contact;
  late final TextEditingController _base;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late TeamStatus _status;
  bool _saving = false;
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    final team = widget.initial;
    _name = TextEditingController(text: team?.teamName ?? '');
    _leader = TextEditingController(text: team?.teamLeader ?? '');
    _contact = TextEditingController(text: team?.contact ?? '');
    _base = TextEditingController(text: team?.baseLocation ?? '');
    _latitude = TextEditingController(
      text: team?.latitude == null ? '' : '${team!.latitude}',
    );
    _longitude = TextEditingController(
      text: team?.longitude == null ? '' : '${team!.longitude}',
    );
    _status = team?.status ?? TeamStatus.available;
  }

  @override
  void dispose() {
    _name.dispose();
    _leader.dispose();
    _contact.dispose();
    _base.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  double? _coordinate(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      await ref.read(rescueTeamServiceProvider).saveTeam(
            teamId: widget.initial?.teamId,
            teamName: _name.text,
            teamLeader: _leader.text,
            contact: _contact.text,
            status: _status,
            latitude: _coordinate(_latitude),
            longitude: _coordinate(_longitude),
            baseLocation: _base.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on InvalidFormError catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on AppError catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Could not save the team: $e']);
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initial == null ? 'Add a rescue team' : 'Edit rescue team',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Team name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a team name.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _leader,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Team leader'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter the leader name.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact number'),
                validator: (v) => (v ?? '')
                        .replaceAll(RegExp(r'[^0-9]'), '')
                        .isEmpty
                    ? 'Enter a contact number.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TeamStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Availability'),
                items: [
                  for (final status in TeamStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _status = v ?? TeamStatus.available),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _base,
                decoration: const InputDecoration(
                  labelText: 'Base / staging location (optional)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latitude,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitude (optional)',
                      ),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return null;
                        final value = double.tryParse(text);
                        if (value == null || value < -90 || value > 90) {
                          return 'Out of range';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _longitude,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitude (optional)',
                      ),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return null;
                        final value = double.tryParse(text);
                        if (value == null || value < -180 || value > 180) {
                          return 'Out of range';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              if (_errors.isNotEmpty)
                Card(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final error in _errors)
                          Text(
                            '• $error',
                            style: const TextStyle(color: Color(0xFFD32F2F)),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save team'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
