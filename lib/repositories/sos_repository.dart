/// SOS persistence repository.
///
/// Storage-only: status transitions are orchestrated by `SosService`, which
/// owns the rules. The UI never touches `Box` directly.
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../models/sos_request.dart';

abstract class SosRepository {
  Stream<List<SosRequest>> watchAll();
  Future<List<SosRequest>> getAll();
  Future<SosRequest?> getById(String sosId);
  Future<void> save(SosRequest request);
  Future<void> delete(String sosId);

  /// Removes every stored SOS. Returns how many were removed.
  Future<int> clear();
}

class HiveSosRepository implements SosRepository {
  HiveSosRepository(this._box);

  final Box _box;

  List<SosRequest> _readAll() {
    final list = <SosRequest>[];
    for (final value in _box.values) {
      list.add(SosRequest.fromMap(value));
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<SosRequest>> watchAll() {
    // Broadcast streams drop events emitted before a listener attaches, and
    // Hive's `Box.watch()` only fires on modifications (never initially). To
    // make the stream self-describing, emit the current snapshot from
    // `onListen` when the first subscriber arrives.
    late final StreamController<List<SosRequest>> controller;
    StreamSubscription<BoxEvent>? sub;
    controller = StreamController<List<SosRequest>>.broadcast(
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
  Future<List<SosRequest>> getAll() async => _readAll();

  @override
  Future<SosRequest?> getById(String sosId) async {
    final value = _box.get(sosId);
    return value == null ? null : SosRequest.fromMap(value);
  }

  @override
  Future<void> save(SosRequest request) async {
    await _box.put(request.sosId, request.toMap());
  }

  @override
  Future<void> delete(String sosId) async {
    await _box.delete(sosId);
  }

  @override
  Future<int> clear() async {
    final removed = _box.length;
    await _box.clear();
    return removed;
  }
}