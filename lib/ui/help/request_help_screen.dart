/// Ask for help: food, water, medicine, a lift, a place to sleep.
///
/// The priority is derived from the category and the number of people by
/// `deriveHelpPriority` — it is shown to the user before saving so the
/// classification is never a hidden judgement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../models/enums/help_category.dart';
import '../../services/help_request_service.dart';
import '../../services/location_service.dart';
import '../widgets/counter_field.dart';
import '../widgets/state_views.dart';

class RequestHelpScreen extends ConsumerStatefulWidget {
  const RequestHelpScreen({super.key});

  @override
  ConsumerState<RequestHelpScreen> createState() => _RequestHelpScreenState();
}

class _RequestHelpScreenState extends ConsumerState<RequestHelpScreen> {
  static const _icons = <HelpCategory, IconData>{
    HelpCategory.rescue: Icons.personal_injury_outlined,
    HelpCategory.food: Icons.restaurant,
    HelpCategory.drinkingWater: Icons.water_drop_outlined,
    HelpCategory.medical: Icons.medical_services_outlined,
    HelpCategory.shelter: Icons.home_work_outlined,
    HelpCategory.transport: Icons.directions_car_outlined,
    HelpCategory.other: Icons.help_outline,
  };

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  HelpCategory _category = HelpCategory.drinkingWater;
  int _people = 1;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(locationStateProvider.notifier).reload());
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  HelpPriority get _priority => deriveHelpPriority(
        category: _category,
        peopleCount: _people,
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final location = ref.read(locationStateProvider).result;
    if (location is! LocationSuccess) {
      _toast('A position is required so a team can find you.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final user = ref.read(currentUserProvider).value;
      final request = await ref.read(helpRequestServiceProvider).createRequest(
            category: _category,
            peopleCount: _people,
            description: _descriptionController.text,
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            reporterId: user?.userId,
            reporterName: user?.displayName,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.helpRequestDetails,
        arguments: request.requestId,
      );
    } on InvalidFormError catch (e) {
      if (mounted) _toast(e.errors.join('\n'));
    } on AppError catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Could not file the request: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationStateProvider);
    final location = locationState.result;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Request help')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const CapabilityNote(
              icon: Icons.info_outline,
              text: 'If people are in immediate danger, send an SOS instead — '
                  'an SOS is relayed over the Bluetooth mesh. A help request '
                  'is stored on this device and is not relayed by this build.',
            ),
            SectionCard(
              title: 'Your position',
              subtitle: switch (location) {
                final LocationSuccess s =>
                  '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}',
                _ => 'Required so a team can find you.',
              },
              trailing: locationState.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(
                    location is LocationSuccess
                        ? Icons.my_location
                        : Icons.location_disabled,
                    color: location is LocationSuccess
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      location is LocationSuccess
                          ? 'Position ready.'
                          : 'No position yet.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: locationState.loading
                        ? null
                        : () => ref
                            .read(locationStateProvider.notifier)
                            .reload(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Use my position'),
                  ),
                ],
              ),
            ),
            if (location is LocationUnavailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  location.message,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'What do you need?',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in HelpCategory.values)
                    ChoiceChip(
                      label: Text(c.label),
                      avatar: Icon(_icons[c], size: 18),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CounterField(
                label: 'How many people?',
                suffix: 'people',
                helper: 'Determines how urgent this is.',
                value: _people,
                min: 1,
                max: Limits.maxPeopleCount,
                onChanged: (v) => setState(() => _people = v),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.priority_high, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Priority: ${_priority.label}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                'Derived from the category and the number of people, using a '
                'fixed rule so a rescue operator can reproduce it.',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                maxLength: Limits.maxFieldNoteLength,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText: 'e.g. 2 adults and a child, no drinking water '
                      'since yesterday…',
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return 'Describe what you need.';
                  if (text.length > Limits.maxFieldNoteLength) {
                    return 'Keep it under ${Limits.maxFieldNoteLength} characters.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_submitting ? 'Filing...' : 'File request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
