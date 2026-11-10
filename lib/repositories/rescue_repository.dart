/// Rescue team persistence (demo teams seeded at bootstrap).
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../models/rescue_team.dart';

abstract class RescueRepository {
  Stream<List<RescueTeam>> watchTeams();
  Future<List<RescueTeam>> getTeams();
  Future<RescueTeam?> getById(String teamId);
  Future<void> saveTeam(RescueTeam team);
}

class HiveRescueRepository implements RescueRepository {
  HiveRescueRepository(this._box);

  final Box _box;

  List<RescueTeam> _readAll() {
    final teams = <RescueTeam>[];
    for (final value in _box.values) {
      teams.add(RescueTeam.fromMap(value));
    }
    teams.sort((a, b) => a.teamName.compareTo(b.teamName));
    return teams;
  }

  @override
  Stream<List<RescueTeam>> watchTeams() {
    // Emit the current snapshot from `onListen` (broadcast streams drop
    // pre-subscription events and `Box.watch()` never fires initially).
    late final StreamController<List<RescueTeam>> controller;
    StreamSubscription<BoxEvent>? sub;
    controller = StreamController<List<RescueTeam>>.broadcast(
      onListen: () {
        controller.add(_readAll());
        sub = _box.watch().listen((_) {
          if (!controller.isClosed) controller.add(_readAll());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<List<RescueTeam>> getTeams() async => _readAll();

  @override
  Future<RescueTeam?> getById(String teamId) async {
    final value = _box.get(teamId);
    return value == null ? null : RescueTeam.fromMap(value);
  }

  @override
  Future<void> saveTeam(RescueTeam team) async {
    await _box.put(team.teamId, team.toMap());
  }
}