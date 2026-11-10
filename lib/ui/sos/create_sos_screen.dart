/// Create SOS: location → people → details → review, then save locally first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/errors/app_error.dart';
import '../../models/enums/emergency_type.dart';
import '../../models/people_info.dart';
import '../../services/location_service.dart';
import '../../services/priority_service.dart';
import '../../services/speech_service.dart';
import '../widgets/badges.dart';
import '../widgets/counter_field.dart';
import '../widgets/offline_map.dart';

class CreateSosScreen extends ConsumerStatefulWidget {
  const CreateSosScreen({super.key});

  @override
  ConsumerState<CreateSosScreen> createState() => _CreateSosScreenState();
}

class _CreateSosScreenState extends ConsumerState<CreateSosScreen> {
  static const _steps = 4;

  int _step = 0;
  bool _submitting = false;

  // Location.
  double? _lat;
  double? _lng;
  double? _accuracy;
  final _latController = TextEditingController(text: '17.7000');
  final _lngController = TextEditingController(text: '83.3000');
  bool _manualLocation = false;

  // People.
  PeopleInfo _people = const PeopleInfo(totalPeople: 1);

  // Emergency details.
  EmergencyType _type = EmergencyType.rescueRequired;
  final _descriptionController = TextEditingController();
  bool _speechBusy = false;

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _applyLocation(LocationResult result) {
    if (result is LocationSuccess) {
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
        _accuracy = result.accuracy;
        _latController.text = result.latitude.toStringAsFixed(6);
        _lngController.text = result.longitude.toStringAsFixed(6);
      });
    }
    // LocationUnavailable is surfaced by the location card, not a crash.
  }

  void _captureLocation() {
    ref.read(locationStateProvider.notifier).reload();
    final state = ref.read(locationStateProvider);
    if (state.result != null) _applyLocation(state.result!);
  }

  PeopleInfo _applyPeople({
    int? total,
    int? children,
    int? elderly,
    int? pregnant,
    int? special,
  }) {
    final next = _people.copyWith(
      totalPeople: total ?? _people.totalPeople,
      childrenCount: children ?? _people.childrenCount,
      elderlyCount: elderly ?? _people.elderlyCount,
      pregnantWomenCount: pregnant ?? _people.pregnantWomenCount,
      specialAssistanceCount: special ?? _people.specialAssistanceCount,
    );
    setState(() => _people = next);
    return next;
  }

  /// Re-evaluate the footer's Next enablement as the description changes, so
  /// the button becomes tappable as soon as the user has typed something.
  void _onDescriptionChanged(String _) {
    setState(() {});
  }

  Future<void> _speechInput() async {
    setState(() => _speechBusy = true);
    try {
      final result =
          await ref.read(speechServiceProvider).recognize();
      if (result is SpeechRecognized && mounted) {
        _descriptionController.text = result.text;
      }
    } catch (e) {
      if (mounted) {
        final message = e is AppError
            ? e.message
            : 'Speech input unavailable on this build.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _speechBusy = false);
    }
  }

  List<String> _draftErrors() {
    final suggestedLat =
        double.tryParse(_latController.text.trim()) ?? _lat;
    final suggestedLng =
        double.tryParse(_lngController.text.trim()) ?? _lng;
    return ref.read(sosServiceProvider).validateDraft(
          people: _people,
          emergencyType: _type,
          description: _descriptionController.text,
          latitude: suggestedLat ?? 0,
          longitude: suggestedLng ?? 0,
        );
  }

  PriorityVerdict? get _liveVerdict =>
      ref.read(priorityServiceProvider).evaluate(
            emergencyType: _type,
            people: _people,
            description: _descriptionController.text,
          );

  Future<void> _send() async {
    final errors = _draftErrors();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.join('\n'))),
      );
      return;
    }

    final user = ref.read(currentUserProvider).value;
    if (user == null) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.onboarding,
        (route) => false,
      );
      return;
    }

    final lat = double.tryParse(_latController.text.trim()) ?? _lat ?? 17.7;
    final lng = double.tryParse(_lngController.text.trim()) ?? _lng ?? 83.3;

    setState(() => _submitting = true);
    try {
      final request = await ref.read(sosServiceProvider).createSos(
            userId: user.userId,
            people: _people,
            emergencyType: _type,
            description: _descriptionController.text,
            latitude: lat,
            longitude: lng,
            accuracy: _accuracy,
          );
      // The SOS is already stored locally at this point, so a link failure
      // cannot lose it. Whether to start the link automatically is a user
      // setting: when it is off, the user starts the link themselves from the
      // confirmation screen or Settings, and the SOS waits in the outbox.
      final autoStart =
          ref.read(autoStartLinkAfterSosProvider).value ?? true;
      if (autoStart) {
        // Permission request only happens because this is an explicit user
        // action.
        await ref
            .read(networkingProvider)
            .start(requestPermissions: true);
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.sosConfirmation,
          arguments: request.sosId,
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is InvalidFormError
            ? e.message
            : e is AppError
                ? e.message
                : 'Could not save the SOS. Please try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep coordinates in sync with the live location result.
    ref.listen(locationStateProvider, (previous, next) {
      final result = next.result;
      if (result is LocationSuccess && result != previous?.result) {
        _applyLocation(result);
      }
    });

    final canNext = switch (_step) {
      0 => true,
      1 => _people.validate().isEmpty && _people.totalPeople >= 1,
      2 => _descriptionController.text.trim().isNotEmpty,
      _ => true,
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Send SOS')),
        body: Column(
          children: [
            _StepIndicator(step: _step, steps: _steps),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: switch (_step) {
                  0 => _LocationStep(
                      key: const ValueKey(0),
                      latController: _latController,
                      lngController: _lngController,
                      accuracy: _accuracy,
                      manual: _manualLocation,
                      onToggleManual: () =>
                          setState(() => _manualLocation = !_manualLocation),
                      onCapture: _captureLocation,
                    ),
                  1 => _PeopleStep(
                      key: const ValueKey(1),
                      people: _people,
                      errors: _people.validate(),
                      onTotalChanged: (v) =>
                          _applyPeople(total: v),
                      onChildrenChanged: (v) =>
                          _applyPeople(children: v),
                      onElderlyChanged: (v) =>
                          _applyPeople(elderly: v),
                      onPregnantChanged: (v) =>
                          _applyPeople(pregnant: v),
                      onSpecialChanged: (v) =>
                          _applyPeople(special: v),
                    ),
                  2 => _DetailsStep(
                      key: const ValueKey(2),
                      type: _type,
                      onTypeChanged: (t) => setState(() => _type = t),
                      controller: _descriptionController,
                      speechBusy: _speechBusy,
                      onSpeech: _speechInput,
                      onDescriptionChanged: _onDescriptionChanged,
                    ),
                  _ => _ReviewStep(
                      key: const ValueKey(3),
                      type: _type,
                      people: _people,
                      description: _descriptionController.text,
                      verdict: _liveVerdict,
                      errors: _draftErrors(),
                    ),
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _step == _steps - 1
                          ? FilledButton.icon(
                              onPressed: _submitting ? null : _send,
                              style: FilledButton.styleFrom(
                                backgroundColor: kDangerColor,
                                foregroundColor: Colors.white,
                              ),
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sos),
                              label: Text(_submitting
                                  ? 'Saving…'
                                  : 'SAVE & TRANSMIT SOS'),
                            )
                          : FilledButton.icon(
                              onPressed: _submitting || !canNext
                                  ? null
                                  : () => setState(() => _step++),
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Next'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.steps});

  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (var i = 0; i < steps; i++) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: i <= step ? scheme.primary : scheme.surfaceContainerHighest,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: i <= step ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (i < steps - 1)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i < step ? scheme.primary : scheme.surfaceContainerHighest,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — location
// ---------------------------------------------------------------------------

class _LocationStep extends ConsumerWidget {
  const _LocationStep({
    super.key,
    required this.latController,
    required this.lngController,
    required this.accuracy,
    required this.manual,
    required this.onToggleManual,
    required this.onCapture,
  });

  final TextEditingController latController;
  final TextEditingController lngController;
  final double? accuracy;
  final bool manual;
  final VoidCallback onToggleManual;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationStateProvider);
    final result = state.result;
    final lat = double.tryParse(latController.text.trim());
    final lng = double.tryParse(lngController.text.trim());

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Where are you?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Your position is attached to the SOS. It can be captured from GPS '
          'or entered manually.',
        ),
        const SizedBox(height: 16),
        if (state.loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Expanded(child: Text('Requesting your location…')),
                ],
              ),
            ),
          )
        else if (result is LocationUnavailable)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.message,
                      style: const TextStyle(color: kDangerColor)),
                  const SizedBox(height: 12),
                  if (result.retriable)
                    OutlinedButton.icon(
                      onPressed: onCapture,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Retry location'),
                    ),
                ],
              ),
            ),
          )
        else if (lat != null && lng != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (accuracy != null) ...[
                        const SizedBox(width: 8),
                        Text('±${accuracy!.toStringAsFixed(0)} m',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  OfflineMap(
                    height: 150,
                    markers: [
                      MapMarker(
                        id: 'self',
                        label: 'You',
                        latitude: lat,
                        longitude: lng,
                        color: const Color(0xFF1565C0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Switch(
              value: manual,
              onChanged: (_) => onToggleManual(),
            ),
            const SizedBox(width: 4),
            const Expanded(child: Text('Enter coordinates manually')),
          ],
        ),
        if (manual) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: lngController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — people
// ---------------------------------------------------------------------------

class _PeopleStep extends StatelessWidget {
  const _PeopleStep({
    super.key,
    required this.people,
    required this.errors,
    required this.onTotalChanged,
    required this.onChildrenChanged,
    required this.onElderlyChanged,
    required this.onPregnantChanged,
    required this.onSpecialChanged,
  });

  final PeopleInfo people;
  final List<String> errors;
  final ValueChanged<int> onTotalChanged;
  final ValueChanged<int> onChildrenChanged;
  final ValueChanged<int> onElderlyChanged;
  final ValueChanged<int> onPregnantChanged;
  final ValueChanged<int> onSpecialChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('How many people are affected?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Counts are used by the priority engine and by rescue teams.'),
        const SizedBox(height: 16),
        CounterField(
          label: 'Total people',
          value: people.totalPeople,
          onChanged: onTotalChanged,
          min: 1,
        ),
        const SizedBox(height: 8),
        CounterField(
          label: 'Children',
          value: people.childrenCount,
          onChanged: onChildrenChanged,
        ),
        const SizedBox(height: 8),
        CounterField(
          label: 'Elderly',
          value: people.elderlyCount,
          onChanged: onElderlyChanged,
        ),
        const SizedBox(height: 8),
        CounterField(
          label: 'Pregnant women',
          value: people.pregnantWomenCount,
          onChanged: onPregnantChanged,
        ),
        const SizedBox(height: 8),
        CounterField(
          label: 'Need special assistance',
          value: people.specialAssistanceCount,
          onChanged: onSpecialChanged,
        ),
        const SizedBox(height: 16),
        if (errors.isNotEmpty)
          Card(
            color: kDangerColor.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in errors)
                    Text('• $e', style: const TextStyle(color: kDangerColor)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — emergency details
// ---------------------------------------------------------------------------

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    super.key,
    required this.type,
    required this.onTypeChanged,
    required this.controller,
    required this.speechBusy,
    required this.onSpeech,
    required this.onDescriptionChanged,
  });

  final EmergencyType type;
  final ValueChanged<EmergencyType> onTypeChanged;
  final TextEditingController controller;
  final bool speechBusy;
  final VoidCallback onSpeech;
  final ValueChanged<String> onDescriptionChanged;

  static const _icons = {
    EmergencyType.rescueRequired: Icons.airline_seat_individual_suite,
    EmergencyType.evacuationRequired: Icons.directions_run,
    EmergencyType.medicalAssistance: Icons.medical_services_outlined,
    EmergencyType.missingPerson: Icons.person_search,
    EmergencyType.foodRequired: Icons.restaurant,
    EmergencyType.drinkingWaterRequired: Icons.water_drop_outlined,
    EmergencyType.shelterRequired: Icons.home_work_outlined,
    EmergencyType.other: Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('What is happening?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in EmergencyType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: type == t,
                avatar: Icon(_icons[t], size: 18),
                onSelected: (_) => onTypeChanged(t),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: controller,
          maxLines: 5,
          maxLength: 600,
          onChanged: onDescriptionChanged,
          decoration: InputDecoration(
            labelText: 'Describe the situation',
            hintText: 'e.g. Water rising, people trapped on the roof…',
            alignLabelWithHint: true,
            suffixIcon: speechBusy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: onSpeech,
                    icon: const Icon(Icons.mic_none),
                    tooltip: 'Voice input (offline)',
                  ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — review
// ---------------------------------------------------------------------------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    super.key,
    required this.type,
    required this.people,
    required this.description,
    required this.verdict,
    required this.errors,
  });

  final EmergencyType type;
  final PeopleInfo people;
  final String description;
  final PriorityVerdict? verdict;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Review & send',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text('${people.totalPeople} people affected'),
                const SizedBox(height: 4),
                Text(description, maxLines: 4, overflow: TextOverflow.ellipsis),
                if (verdict != null) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      PriorityBadge(priority: verdict!.priority),
                      const Spacer(),
                      Text('Score ${verdict!.score}',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Why this priority:',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  for (final reason in verdict!.reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $reason',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your SOS is stored on this device the moment you tap send — even if '
          'no other device is reachable, it is never lost. Transmission then '
          'hops device-to-device over the Bluetooth mesh.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: kDangerColor.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in errors)
                    Text('• $e', style: const TextStyle(color: kDangerColor)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}