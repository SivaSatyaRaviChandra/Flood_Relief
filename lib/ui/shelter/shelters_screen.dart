/// Shelters and safe locations known to this device.
///
/// The list starts empty. This build ships **no** shelter seed data because
/// inventing shelter names, capacities or phone numbers for a real district
/// would be unsafe — an entry that looks authoritative but is fictional is
/// worse than an empty list. Users and rescue operators add real ones.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../models/shelter.dart';
import '../../services/shelter_service.dart';
import '../widgets/badges.dart';
import '../widgets/counter_field.dart';
import '../widgets/state_views.dart';

class SheltersScreen extends ConsumerStatefulWidget {
  const SheltersScreen({super.key});

  @override
  ConsumerState<SheltersScreen> createState() => _SheltersScreenState();
}

class _SheltersScreenState extends ConsumerState<SheltersScreen> {
  bool _spaceOnly = false;

  @override
  Widget build(BuildContext context) {
    final sheltersAsync = ref.watch(sheltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add a shelter',
            onPressed: () => _edit(context, ref, null),
          ),
        ],
      ),
      body: sheltersAsync.when(
        loading: () => const LoadingStateView(message: 'Reading shelters...'),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(sheltersProvider),
        ),
        data: (all) {
          final filtered = _spaceOnly
              ? all.where((s) => s.open && s.availableCapacity > 0).toList()
              : all;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('With space'),
                      selected: _spaceOnly,
                      onSelected: (v) => setState(() => _spaceOnly = v),
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
                        icon: Icons.home_work_outlined,
                        title: all.isEmpty
                            ? 'No shelters added yet'
                            : 'No shelter has space',
                        message: all.isEmpty
                            ? 'Add the shelters and camps in your area with '
                                'their real capacity and contact number. This '
                                'app ships with none, because a made-up shelter '
                                'is more dangerous than a missing one.'
                            : 'Every shelter here is full or closed. Check '
                                'again later or contact a rescue operator.',
                        action: all.isEmpty
                            ? FilledButton.icon(
                                onPressed: () => _edit(context, ref, null),
                                icon: const Icon(Icons.add),
                                label: const Text('Add a shelter'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: () async => ref.refresh(sheltersProvider.future),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 32),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              ShelterTile(shelter: filtered[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Shelter? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ShelterForm(
        shelterId: existing?.shelterId,
        initial: existing,
      ),
    );
  }
}

class ShelterTile extends StatelessWidget {
  const ShelterTile({super.key, required this.shelter});

  final Shelter shelter;

  @override
  Widget build(BuildContext context) {
    final noSpace = !shelter.open || shelter.availableCapacity == 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: noSpace
              ? const Color(0xFFC62828).withValues(alpha: 0.12)
              : const Color(0xFF2E7D32).withValues(alpha: 0.12),
          child: Icon(
            noSpace ? Icons.do_not_disturb_on : Icons.home_work,
            color: noSpace ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
          ),
        ),
        title: Text(
          shelter.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShelterStatusChip(shelter: shelter),
              Text(
                shelter.capacity <= 0
                    ? '${shelter.occupied} people · capacity unknown'
                    : '${shelter.occupied}/${shelter.capacity} places taken',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => AppNav.pushShelterDetails(context, shelter.shelterId),
      ),
    );
  }
}

/// Detail screen: the record plus the occupancy actions.
///
/// The id arrives through the route arguments (`AppNav.pushShelterDetails` or
/// a plain `pushNamed`), so this screen is registered as a named route without
/// a closure. Pass [shelterId] directly to open it outside the router.
class ShelterDetailsScreen extends ConsumerWidget {
  const ShelterDetailsScreen({super.key, this.shelterId});

  /// Overrides the route argument. Null means "read it from the route".
  final String? shelterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    final id = shelterId ?? (argument is String ? argument : null);
    final shelters = ref.watch(sheltersProvider);
    final scheme = Theme.of(context).colorScheme;

    if (id == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shelter')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'No shelter selected',
          message: 'Open this screen from the shelters list.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit this shelter',
            onPressed: () {
              final matches =
                  shelters.value?.where((s) => s.shelterId == shelterId) ?? const <Shelter>[];
              if (matches.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('This shelter is no longer stored.')),
                );
                return;
              }
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _ShelterForm(
                  shelterId: matches.first.shelterId,
                  initial: matches.first,
                ),
              );
            },
          ),
        ],
      ),
      body: shelters.when(
        loading: () => const LoadingStateView(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(sheltersProvider),
        ),
        data: (all) {
          final matches = all.where((s) => s.shelterId == id);
          if (matches.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Shelter not found',
              message: 'It was deleted, or it was added on another device. '
                  'This build does not sync shelters between devices.',
            );
          }
          final shelter = matches.first;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SectionCard(
                title: shelter.name,
                subtitle: shelter.address ?? 'No address recorded',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [ShelterStatusChip(shelter: shelter)],
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      label: 'Capacity',
                      value: shelter.capacity <= 0
                          ? 'Unknown'
                          : '${shelter.capacity} places',
                    ),
                    _Field(
                      label: 'Occupied',
                      value: '${shelter.occupied} people',
                    ),
                    _Field(
                      label: 'Free places',
                      value: shelter.capacity <= 0
                          ? 'Unknown (no capacity recorded)'
                          : '${shelter.availableCapacity}',
                    ),
                    if (shelter.hasCoordinates)
                      _Field(
                        label: 'Position',
                        value: '${shelter.latitude!.toStringAsFixed(5)}, '
                            '${shelter.longitude!.toStringAsFixed(5)}',
                      ),
                    if (shelter.contactPhone != null)
                      _Field(label: 'Contact', value: shelter.contactPhone!),
                    if (shelter.notes != null)
                      _Field(label: 'Notes', value: shelter.notes!),
                    if (shelter.facilities.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Facilities',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final f in shelter.facilities)
                            Chip(label: Text(f)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SectionCard(
                title: 'Record movement',
                subtitle: 'Occupancy drives the status shown above, so it is '
                    'the source of truth.',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _record(
                              context,
                              ref,
                              id,
                              (service, id) =>
                                  service.recordArrival(id, 1),
                              '1 arrival recorded.',
                            ),
                            icon: const Icon(Icons.login),
                            label: const Text('Arrival'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _record(
                              context,
                              ref,
                              id,
                              (service, id) =>
                                  service.recordDeparture(id, 1),
                              '1 departure recorded.',
                            ),
                            icon: const Icon(Icons.logout),
                            label: const Text('Departure'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () => _editOccupancy(context, ref, id, shelter),
                      icon: const Icon(Icons.tune),
                      label: const Text('Set occupancy exactly'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _setOpen(context, ref, shelter, !shelter.open),
                      icon: Icon(shelter.open ? Icons.lock_outline : Icons.lock_open),
                      label: Text(shelter.open
                          ? 'Mark as not accepting people'
                          : 'Mark as accepting people'),
                    ),
                    if (shelter.capacity <= 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No capacity is recorded, so arrivals are counted '
                          'without a limit and the status stays "almost full".',
                          style: TextStyle(fontSize: 12, color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Danger zone',
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDelete(context, ref, shelter),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete this shelter'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    String id,
    Future<Shelter> Function(ShelterService service, String id) action,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(shelterServiceProvider), id);
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not record that: $e')),
      );
    }
  }

  Future<void> _editOccupancy(
    BuildContext context,
    WidgetRef ref,
    String id,
    Shelter shelter,
  ) async {
    final controller = TextEditingController(text: '${shelter.occupied}');
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set occupancy'),
        content: NumberTextField(
          controller: controller,
          label: 'People currently inside',
          helper: shelter.capacity <= 0
              ? 'No capacity recorded for this shelter.'
              : 'Must be between 0 and ${shelter.capacity}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shelterServiceProvider).setOccupancy(id, value);
      messenger.showSnackBar(
        SnackBar(content: Text('Occupancy set to $value.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not set it: $e')));
    }
  }

  Future<void> _setOpen(
    BuildContext context,
    WidgetRef ref,
    Shelter shelter,
    bool open,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shelterServiceProvider).setOpen(shelter.shelterId, open);
      messenger.showSnackBar(
        SnackBar(
          content: Text(open
              ? 'Now accepting people.'
              : 'Marked as not accepting people.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Shelter shelter,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${shelter.name}?'),
        content: const Text(
          'The shelter will be removed from this device. This cannot be '
          'undone.',
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
      await ref.read(shelterServiceProvider).delete(shelter.shelterId);
      messenger.showSnackBar(const SnackBar(content: Text('Shelter deleted.')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }
}

/// Create/edit form. Lives in a bottom sheet so it works from both the list
/// and the detail screen without duplicating the fields.
class _ShelterForm extends ConsumerStatefulWidget {
  const _ShelterForm({this.shelterId, this.initial});

  final String? shelterId;
  final Shelter? initial;

  @override
  ConsumerState<_ShelterForm> createState() => _ShelterFormState();
}

class _ShelterFormState extends ConsumerState<_ShelterForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _capacityController;
  late final TextEditingController _occupiedController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;
  final _facilitiesController = TextEditingController();
  late bool _open;
  bool _saving = false;
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _nameController = TextEditingController(text: s?.name ?? '');
    _addressController = TextEditingController(text: s?.address ?? '');
    _capacityController = TextEditingController(text: '${s?.capacity ?? 0}');
    _occupiedController = TextEditingController(text: '${s?.occupied ?? 0}');
    _phoneController = TextEditingController(text: s?.contactPhone ?? '');
    _notesController = TextEditingController(text: s?.notes ?? '');
    _facilitiesController.text = (s?.facilities ?? const []).join(', ');
    _open = s?.open ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _capacityController.dispose();
    _occupiedController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _facilitiesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      await ref.read(shelterServiceProvider).saveShelter(
            shelterId: widget.shelterId,
            name: _nameController.text,
            capacity: int.tryParse(_capacityController.text.trim()) ?? 0,
            occupied: int.tryParse(_occupiedController.text.trim()) ?? 0,
            address: _addressController.text,
            contactPhone: _phoneController.text,
            notes: _notesController.text,
            facilities: _facilitiesController.text
                .split(',')
                .map((f) => f.trim())
                .where((f) => f.isNotEmpty)
                .toList(),
            open: _open,
          );
      if (mounted) Navigator.of(context).pop();
    } on InvalidFormError catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on AppError catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Could not save: $e']);
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
                widget.shelterId == null ? 'Add a shelter' : 'Edit shelter',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address / landmark (optional)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NumberTextField(
                      controller: _capacityController,
                      label: 'Capacity',
                      helper: '0 = unknown',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NumberTextField(
                      controller: _occupiedController,
                      label: 'Occupied',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact number (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _facilitiesController,
                decoration: InputDecoration(
                  labelText: 'Facilities (comma separated)',
                  helperText: 'At most ${Limits.maxShelterFacilities}, e.g. '
                      'drinking water, medical, blankets',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _open,
                onChanged: (v) => setState(() => _open = v),
                title: const Text('Accepting people'),
                subtitle: const Text(
                  'Turn off when the shelter has stopped taking arrivals.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_errors.isNotEmpty)
                Card(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in _errors)
                          Text(
                            '• $e',
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
                label: Text(_saving ? 'Saving...' : 'Save shelter'),
              ),
            ],
          ),
        ),
      ),
    );
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
            width: 130,
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
