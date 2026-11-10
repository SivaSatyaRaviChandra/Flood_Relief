/// Post-send screen: honest transmission status. The SOS is already saved;
/// "received by rescue" only appears after a real ACK arrives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../widgets/badges.dart';
import '../widgets/offline_map.dart';

class SosConfirmationScreen extends ConsumerWidget {
  const SosConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosId = ModalRoute.of(context)!.settings.arguments as String?;
    final requestAsync = ref.watch(sosByIdProvider(sosId ?? ''));
    final linkStatus = ref.watch(communicationStatusProvider).value;
    final request = requestAsync.value;

    final acknowledged = request?.acknowledged ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS sent'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            acknowledged ? Icons.check_circle : Icons.saved_search,
            size: 72,
            color: acknowledged ? const Color(0xFF2E7D32) : kDangerColor,
          ),
          const SizedBox(height: 12),
          Text(
            acknowledged
                ? 'Received by rescue'
                : 'SOS saved on this device',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: acknowledged
                      ? const Color(0xFF2E7D32)
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
          if (sosId != null) ...[
            const SizedBox(height: 8),
            Text(
              sosId,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          LinkStatusBanner(status: linkStatus),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What happens next?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Your SOS is stored locally — it is never lost even '
                    'without any connection.\n'
                    '2. It hops over the Bluetooth mesh (device → relay → '
                    'recovery node).\n'
                    '3. When rescue confirms, you will see "Received by '
                    'rescue" here — only after a real acknowledgement.',
                  ),
                  if (request != null) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        StatusChip(status: request.status),
                        const SizedBox(width: 8),
                        PriorityBadge(priority: request.priority),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OfflineMap(
                      height: 160,
                      markers: [
                        MapMarker(
                          id: request.sosId,
                          label: request.sosId,
                          latitude: request.latitude,
                          longitude: request.longitude,
                          color: kDangerColor,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!acknowledged)
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(networkingProvider)
                    .start(requestPermissions: true);
              },
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Search for relay / rescue now'),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}