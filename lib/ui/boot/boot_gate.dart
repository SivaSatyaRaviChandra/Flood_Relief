/// Boot gate: the first route, and the only place that decides where a launch
/// lands.
///
/// The previous splash screen was a dead end — it rendered the app icon and a
/// manual "Get started" arrow, so a launch that never received that tap showed
/// nothing but a logo forever. [BootGate] resolves the persisted state and
/// routes automatically, so there is no screen the user can get stuck on.
///
/// Decision table (first match wins):
///  * no signed-in user              → onboarding
///  * rescue user, no team selected  → rescue login
///  * rescue user, team selected     → rescue dashboard
///  * otherwise                      → home
///
/// While the decision is being made a small splash is shown, and if the state
/// itself cannot be read the gate reports the failure with a retry action
/// instead of falling through to a blank screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_surface.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../models/app_user.dart';

class BootGate extends ConsumerStatefulWidget {
  const BootGate({super.key});

  @override
  ConsumerState<BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<BootGate> {
  /// The route already pushed, so a rebuild (e.g. the user state resolving
  /// again) never stacks a second copy of the same screen.
  String? _routedTo;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const _BootSplash(message: 'Starting FloodRelief...'),
      error: (error, stack) => _BootFailure(
        error: error,
        onRetry: () => ref.invalidate(currentUserProvider),
      ),
      data: (user) => _routeFor(user),
    );
  }

  Widget _routeFor(AppUser? user) {
    // No user: onboarding registers one and is the only screen that can
    // create it, so the gate must never loop back here on its own.
    final target = user == null
        ? AppRoutes.onboarding
        : user.isRescue
            ? (user.teamId == null || user.teamId!.isEmpty
                ? AppRoutes.rescueLogin
                : AppRoutes.rescueDashboard)
            : AppRoutes.home;

    if (_routedTo != target) {
      _routedTo = target;
      // `addPostFrameCallback` because replacing the navigator stack from
      // inside a build would mutate the tree during layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
      });
    }
    return const _BootSplash(message: 'Starting FloodRelief...');
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emergency_share, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'FloodRelief',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            const Text('Offline-first emergency mesh'),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the persisted sign-in state cannot be read at all.
class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('FloodRelief could not start')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'FloodRelief could not read your local data.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                describe(error),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your stored records are untouched. Retry to read them again, '
              'or copy this message for a bug report.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: errorLog.entries.isEmpty
                  ? null
                  : () => showErrorLogDialog(context),
              icon: const Icon(Icons.bug_report_outlined),
              label: Text(
                errorLog.isEmpty
                    ? 'No recorded errors'
                    : 'View ${errorLog.length} recorded error(s)',
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.onboarding,
                (route) => false,
              ),
              child: const Text('Continue without an account'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the bounded [errorLog] in a dialog. Shared by the boot gate and
/// Settings → Diagnostics.
Future<void> showErrorLogDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Recorded errors'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in errorLog.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.source} · ${entry.at.toIso8601String()}',
                      style: Theme.of(dialogContext).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      entry.summary,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            if (errorLog.isEmpty)
              const Text('Nothing has been recorded since launch.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: errorLog.isEmpty
              ? null
              : () {
                  errorLog.clear();
                  Navigator.of(dialogContext).pop();
                },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
