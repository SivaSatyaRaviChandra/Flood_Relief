/// Report the state of the water where you are standing.
///
/// Deliberately a *report*, not an SOS: it describes conditions. Filing one is
/// stored on this device immediately and never depends on connectivity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../models/enums/flood_severity.dart';
import '../../services/location_service.dart';
import '../widgets/badges.dart';
import '../widgets/counter_field.dart';
import '../widgets/state_views.dart';

class ReportFloodScreen extends ConsumerStatefulWidget {
  const ReportFloodScreen({super.key});

  @override
  ConsumerState<ReportFloodScreen> createState() => _ReportFloodScreenState();
}

class _ReportFloodScreenState extends ConsumerState<ReportFloodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  FloodSeverity _severity = FloodSeverity.medium;
  WaterDepthCategory _depth = WaterDepthCategory.ankleDeep;
  int _affected = 0;
  bool _submitting = false;
  bool _usedCapturedLocation = false;

  @override
  void initState() {
    super.initState();
    // Capture a position immediately: the user is in the field and the
    // screen is useless without a location. It is a single attempt — no
    // permission prompt is forced here, the notifier surfaces any denial.
    Future.microtask(() => ref.read(locationStateProvider.notifier).reload());
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final location = ref.read(locationStateProvider).result;
    if (location is! LocationSuccess) {
      _toast(
        'A position is required. Enable location and tap "Use my position".',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final user = ref.read(currentUserProvider).value;
      final report = await ref.read(floodReportServiceProvider).createReport(
            severity: _severity,
            waterDepth: _depth,
            affectedPeople: _affected,
            description: _descriptionController.text,
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            reporterId: user?.userId,
            reporterName: user?.displayName,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.floodReports,
        arguments: report.reportId,
      );
    } on InvalidFormError catch (e) {
      if (mounted) _toast(e.errors.join('\n'));
    } on AppError catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Could not save the report: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationStateProvider).result;
    final locationState = ref.watch(locationStateProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Report flooding')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const CapabilityNote(
              icon: Icons.phone_android,
              text: 'Reports are saved on this device straight away. This '
                  'build does not relay flood reports over the Bluetooth '
                  'mesh — the packet protocol carries SOS and acknowledgements '
                  'only. Reports are visible to rescue operators who open this '
                  'device.',
            ),
            _LocationCard(
              state: locationState,
              usedCaptured: _usedCapturedLocation,
              onUse: () {
                ref.read(locationStateProvider.notifier).reload();
                setState(() => _usedCapturedLocation = false);
              },
            ),
            if (location is LocationUnavailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  location.message,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'How severe is it?',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in FloodSeverity.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _severity == s,
                    onSelected: (_) => setState(() => _severity = s),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'How deep is the water?',
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
                  for (final d in WaterDepthCategory.values)
                    ChoiceChip(
                      label: Text(d.label),
                      selected: _depth == d,
                      onSelected: (_) => setState(() => _depth = d),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CounterField(
                label: 'People affected',
                helper: 'Count only what you can see.',
                value: _affected,
                max: Limits.maxPeopleCount,
                onChanged: (v) => setState(() => _affected = v),
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
                  labelText: 'What can you see?',
                  hintText: 'e.g. Main road under 1m, ground floor flooded…',
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return 'Describe what you can see.';
                  if (text.length > Limits.maxFieldNoteLength) {
                    return 'Keep it under ${Limits.maxFieldNoteLength} characters.';
                  }
                  return null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  FloodSeverityChip(severity: _severity),
                  const SizedBox(width: 8),
                  WaterDepthChip(depth: _depth),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
                    : const Icon(Icons.save_outlined),
                label: Text(_submitting ? 'Saving...' : 'Save report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.state,
    required this.usedCaptured,
    required this.onUse,
  });

  final LocationState state;
  final bool usedCaptured;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    final ok = result is LocationSuccess;
    return SectionCard(
      title: 'Report position',
      subtitle: switch (result) {
        final LocationSuccess s =>
          '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}',
        _ => 'Required before a report can be filed.',
      },
      trailing: state.loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: Row(
        children: [
          Icon(
            ok ? Icons.my_location : Icons.location_disabled,
            color: ok
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? (usedCaptured
                      ? 'Position captured on this device.'
                      : 'Position ready.')
                  : 'No position yet.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton.icon(
            onPressed: state.loading ? null : onUse,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Use my position'),
          ),
        ],
      ),
    );
  }
}
