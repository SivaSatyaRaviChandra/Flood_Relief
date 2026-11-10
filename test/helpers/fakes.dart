/// Shared in-memory fakes for unit tests:
/// * [MemorySosRepository] — a live [SosRepository] with no file I/O.
/// * [RecordingTransport] — a [BleTransport] that records broadcasts and can
///   simulate a down link.
library;

import 'dart:async';

import 'package:flood_relief/models/rescue_team.dart';
import 'package:flood_relief/models/sos_request.dart';
import 'package:flood_relief/repositories/rescue_repository.dart';
import 'package:flood_relief/repositories/sos_repository.dart';
import 'package:flood_relief/services/ble/ble_transport.dart';

/// In-memory [SosRepository] for unit tests (mirrors Hive semantics: newest
/// first, watch stream self-describes on first listen).
class MemorySosRepository implements SosRepository {
  final Map<String, SosRequest> _store = {};
  final _controller = StreamController<List<SosRequest>>.broadcast();

  List<SosRequest> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<SosRequest>> watchAll() async* {
    yield _readAll();
    yield* _controller.stream;
  }

  @override
  Future<List<SosRequest>> getAll() async => _readAll();

  @override
  Future<SosRequest?> getById(String sosId) async => _store[sosId];

  @override
  Future<void> save(SosRequest request) async {
    _store[request.sosId] = request;
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> delete(String sosId) async {
    _store.remove(sosId);
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<int> clear() async {
    final removed = _store.length;
    _store.clear();
    if (!_controller.isClosed) _controller.add(_readAll());
    return removed;
  }

  void dispose() => _controller.close();
}

/// In-memory [RescueRepository] for tests. Team writes complete synchronously,
/// so team management flows never block inside `testWidgets`' fake-async zone.
class MemoryRescueRepository implements RescueRepository {
  MemoryRescueRepository([Iterable<RescueTeam> seed = const []]) {
    for (final team in seed) {
      _store[team.teamId] = team;
    }
  }

  final Map<String, RescueTeam> _store = {};
  final _controller = StreamController<List<RescueTeam>>.broadcast();

  List<RescueTeam> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) => a.teamName.compareTo(b.teamName));
    return list;
  }

  @override
  Stream<List<RescueTeam>> watchTeams() async* {
    yield _readAll();
    yield* _controller.stream;
  }

  @override
  Future<List<RescueTeam>> getTeams() async => _readAll();

  @override
  Future<RescueTeam?> getById(String teamId) async => _store[teamId];

  @override
  Future<void> saveTeam(RescueTeam team) async {
    _store[team.teamId] = team;
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  void dispose() => _controller.close();
}

/// A [BleTransport] that records every broadcast payload. When
/// [failBroadcast] is true, [broadcast] throws (simulating no reachable peer).
class RecordingTransport implements BleTransport {
  RecordingTransport({
    this.failBroadcast = false,
    this.nodeId = 'DEVICE-NODE',
  });

  final bool failBroadcast;

  final String nodeId;

  final List<String> sent = <String>[];
  final _state = StreamController<BleTransportState>.broadcast();
  final _incoming = StreamController<ReceivedPacket>.broadcast();

  @override
  String get localDeviceId => nodeId;

  @override
  Stream<BleTransportState> get state => _state.stream;

  @override
  Stream<ReceivedPacket> get incoming => _incoming.stream;

  @override
  Future<void> start({bool requestPermissions = false}) async {
    if (!_state.isClosed) _state.add(BleTransportState.advertising);
  }

  @override
  Future<void> stop() async {
    if (!_state.isClosed) _state.add(BleTransportState.idle);
  }

  @override
  Future<void> broadcast(String payload) async {
    if (failBroadcast) throw Exception('link down');
    sent.add(payload);
  }

  @override
  Future<void> dispose() async {
    await _state.close();
    await _incoming.close();
  }
}