/// First-run onboarding: introduce the app and register the local user.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../models/app_user.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  UserRole _role = UserRole.affected;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final deviceId = ref.read(deviceIdProvider);
    final suffix = deviceId.replaceFirst('DEVICE-', '');
    final user = AppUser(
      userId: _role == UserRole.affected
          ? 'USER-$suffix'
          : 'RESCUE-$suffix',
      displayName: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      role: _role,
      createdAt: DateTime.now().toUtc(),
    );

    try {
      await ref.read(currentUserProvider.notifier).signIn(user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save your details: $e')),
      );
      return;
    }

    // Recorded so Settings can report it, and so a later version of the boot
    // gate can tell "never onboarded" from "signed out".
    //
    // Deliberately *not* awaited before navigating: the user is already
    // registered at this point, and a failure here must not strand them on a
    // form they have already completed. The failure is reported instead.
    unawaited(
      ref
          .read(onboardingCompleteProvider.notifier)
          .set(true)
          .catchError((Object e) => debugPrint('FloodRelief: onboarding flag '
              'not stored: $e')),
    );

    if (mounted) {
      setState(() => _saving = false);
      if (_role == UserRole.affected) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
      } else {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.rescueLogin, (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Icon(Icons.emergency_share,
                    size: 64, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  'FloodRelief',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Offline-first flood SOS & rescue coordination.\nWorks without '
                  'Wi-Fi or mobile data — SOSs hop device-to-device over '
                  'Bluetooth.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),
                Text('I am joining as:',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _RoleCard(
                  icon: Icons.person_pin_circle_outlined,
                  title: 'Affected person',
                  subtitle: 'Send SOS and track its journey',
                  selected: _role == UserRole.affected,
                  onTap: () => setState(() => _role = UserRole.affected),
                ),
                const SizedBox(height: 8),
                _RoleCard(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Rescue team',
                  subtitle: 'View SOSs, assign teams, track rescues',
                  selected: _role == UserRole.rescue,
                  onTap: () => setState(() => _role = UserRole.rescue),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _continue,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(_saving
                      ? 'Starting...'
                      : _role == UserRole.affected
                          ? 'Continue as affected person'
                          : 'Continue as rescue operator'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'All data stays on this device (local-first). No account or '
                  'internet is required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.6)
              : scheme.surface,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.radio_button_checked, color: scheme.primary)
            else
              Icon(Icons.radio_button_unchecked,
                  color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}