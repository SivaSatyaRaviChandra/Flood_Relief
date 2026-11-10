/// Demo panel: exercises the full relay chain (You → B → C → Rescue) using
/// the in-process simulated mesh, plus a live log of routing decisions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../services/ble/packet_router.dart';
import '../../services/demo/demo_controller.dart';
import '../widgets/badges.dart';

class DemoPanelScreen extends ConsumerStatefulWidget {
  const DemoPanelScreen({super.key});

  @override
  ConsumerState<DemoPanelScreen> createState() => _DemoPanelScreenState();
}

class _DemoPanelScreenState extends ConsumerState<DemoPanelScreen> {
  String? _targetSosId;
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(demoControllerProvider);
    final all = ref.watch(allSosProvider).value ?? const [];
    final linkStatus = ref.watch(communicationStatusProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Demo & simulation')),
      body: demo == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Demo mode is unavailable. Enable it in Settings (or start '
                  'the app with demo data) and restart.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                LinkStatusBanner(status: linkStatus),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'This panel runs a simulated relay chain on one device: '
                    '[You] → DEVICE-DEMOB1 → DEVICE-DEMOC2 → DEVICE-RESCUE. '
                    'Send an SOS or inject packets and watch the routing log.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _DemoAction(
                        icon: Icons.add_alert,
                        title: 'Simulate a new SOS from you',
                        busy: _busy,
                        onTap: () => _guard(() async {
                          final sos = await demo.simulateNewSos();
                          await ref
                              .read(networkingProvider)
                              .start(requestPermissions: true);
                          _openConfirmation(sos.sosId);
                        }),
                      ),
                      const SizedBox(height: 8),
                      _DemoAction(
                        icon: Icons.south_west,
                        title: 'Simulate SOS from another device',
                        busy: _busy,
                        onTap: () =>
                            _guard(() => demo.simulateIncomingFromAnotherDevice()),
                      ),
                      const SizedBox(height: 8),
                      _DemoAction(
                        icon: Icons.mark_email_read_outlined,
                        title: 'Simulate ACK from rescue',
                        busy: _busy,
                        onTap: () =>
                            _guard(() => demo.simulateAckFromRescue(_targetSosId)),
                      ),
                      const SizedBox(height: 8),
                      _DemoAction(
                        icon: Icons.wifi_tethering,
                        title: 'Restart mesh & link',
                        busy: _busy,
                        onTap: () => _guard(() =>
                            ref.read(networkingProvider).start()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Status machine actions on a selected SOS.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Status machine demo',
                              style:
                                  TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _targetSosId,
                            items: [
                              for (final sos in all)
                                DropdownMenuItem(
                                  value: sos.sosId,
                                  child: Text(
                                      '${sos.sosId} (${sos.status.label})'),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _targetSosId = v),
                            decoration:
                                const InputDecoration(labelText: 'Select SOS'),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _targetSosId == null || _busy
                                    ? null
                                    : () => _guard(() =>
                                        demo.assignTeam(_targetSosId!, 'TEAM-002')),
                                child: const Text('Assign team'),
                              ),
                              OutlinedButton(
                                onPressed: _targetSosId == null || _busy
                                    ? null
                                    : () => _guard(() =>
                                        demo.startRescue(_targetSosId!)),
                                child: const Text('Start rescue'),
                              ),
                              OutlinedButton(
                                onPressed: _targetSosId == null || _busy
                                    ? null
                                    : () => _guard(() =>
                                        demo.resolveSos(_targetSosId!)),
                                child: const Text('Resolve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Demo log',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                _LogStream(source: demo.events),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Routing decisions',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                _RoutingLogView(),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Queue events',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                _QueueEventsView(),
              ],
            ),
    );
  }

  void _openConfirmation(String sosId) {
    if (!mounted) return;
    Navigator.of(context).pushNamed(
      AppRoutes.sosConfirmation,
      arguments: sosId,
    );
  }
}

class _DemoAction extends StatelessWidget {
  const _DemoAction({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.busy,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle_outline),
        onTap: busy ? null : onTap,
      ),
    );
  }
}

/// Renders the demo controller log stream (a broadcast stream of strings).
class _LogStream extends ConsumerStatefulWidget {
  const _LogStream({required this.source});

  final Stream<DemoLogEntry> source;

  @override
  ConsumerState<_LogStream> createState() => _LogStreamState();
}

class _LogStreamState extends ConsumerState<_LogStream> {
  final List<String> _lines = [];

  @override
  void initState() {
    super.initState();
    widget.source.listen((entry) {
      if (mounted) {
        setState(() => _lines.insert(0, entry.message));
        if (_lines.length > 30) _lines.removeRange(30, _lines.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _LogCard(lines: _lines);
  }
}

class _RoutingLogView extends ConsumerStatefulWidget {
  const _RoutingLogView();

  @override
  ConsumerState<_RoutingLogView> createState() => _RoutingLogViewState();
}

class _RoutingLogViewState extends ConsumerState<_RoutingLogView> {
  final List<String> _lines = [];

  @override
  Widget build(BuildContext context) {
    ref.listen(routingEventsProvider, (previous, next) {
      final event = next.value;
      if (event == null) return;
      final decision = event.decision;
      final color = switch (decision) {
        RoutingDecision.duplicate ||
        RoutingDecision.invalidPacket ||
        RoutingDecision.replayRejected =>
          const Color(0xFFC62828),
        RoutingDecision.ttlExpired => const Color(0xFFB26A00),
        RoutingDecision.acceptedForwarded ||
        RoutingDecision.outgoingQueued =>
          const Color(0xFF2E7D32),
        _ => const Color(0xFF1565C0),
      };
      _push('${_dot(color)} ${event.decision.name}: ${event.detail}');
    });
    return _LogCard(lines: _lines.toList().reversed.toList());
  }

  static String _dot(Color color) => '•';

  void _push(String line) {
    if (!mounted) return;
    setState(() {
      _lines.add(line);
      if (_lines.length > 40) _lines.removeAt(0);
    });
  }
}

class _QueueEventsView extends ConsumerStatefulWidget {
  const _QueueEventsView();

  @override
  ConsumerState<_QueueEventsView> createState() => _QueueEventsViewState();
}

class _QueueEventsViewState extends ConsumerState<_QueueEventsView> {
  final List<String> _lines = [];

  @override
  Widget build(BuildContext context) {
    ref.listen(queueEventsProvider, (previous, next) {
      final event = next.value;
      if (event == null) return;
      _push('${event.kind.name}: ${event.message}');
    });
    return _LogCard(lines: _lines.toList().reversed.toList());
  }

  void _push(String line) {
    if (!mounted) return;
    setState(() {
      _lines.add(line);
      if (_lines.length > 40) _lines.removeAt(0);
    });
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: lines.isEmpty
            ? const Text('No events yet.', style: TextStyle(color: Colors.grey))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        line,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}