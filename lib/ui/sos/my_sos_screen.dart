/// "My SOSs": all SOS records created by the current user.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../widgets/sos_card.dart';

class MySosScreen extends ConsumerWidget {
  const MySosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mySos = ref.watch(mySosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My SOSs')),
      body: mySos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load SOSs: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('You have not sent any SOS yet.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => AppNav.pushNamed(context, AppRoutes.createSos),
                    icon: const Icon(Icons.sos),
                    label: const Text('Send SOS'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(allSosProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final sos = list[index];
                return SosCard(
                  request: sos,
                  onTap: () => AppNav.pushSosDetails(context, sos.sosId),
                );
              },
            ),
          );
        },
      ),
    );
  }
}