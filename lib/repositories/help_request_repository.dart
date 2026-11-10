/// Help request persistence.
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/errors/app_error.dart';
import '../core/utils/geo.dart';
import '../models/help_request.dart';
import 'hive_stream_support.dart';

abstract class HelpRequestRepository {
  Stream<List<HelpRequest>> watchAll();
  Future<List<HelpRequest>> getAll();
  Future<HelpRequest?> getById(String requestId);
  Future<void> save(HelpRequest request);
  Future<void> delete(String requestId);
  Future<void> clear();

  Future<List<HelpRequest>> nearby({
    double? latitude,
    double? longitude,
    double radiusMetres = 5000,
  });
}

class HiveHelpRequestRepository implements HelpRequestRepository {
  HiveHelpRequestRepository(this._box);

  final Box _box;

  List<HelpRequest> _readAll() {
    final list = <HelpRequest>[];
    for (final value in _box.values) {
      list.add(HelpRequest.fromMap(value));
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<HelpRequest>> watchAll() => watchBoxSnapshot(_box, _readAll);

  @override
  Future<List<HelpRequest>> getAll() async => _readAll();

  @override
  Future<HelpRequest?> getById(String requestId) async {
    final value = _box.get(requestId);
    return value == null ? null : HelpRequest.fromMap(value);
  }

  @override
  Future<void> save(HelpRequest request) async {
    try {
      await _box.put(request.requestId, request.toMap());
    } catch (e) {
      throw DatabaseError(
        'Could not store the help request on this device.',
        cause: e,
      );
    }
  }

  @override
  Future<void> delete(String requestId) async => _box.delete(requestId);

  @override
  Future<void> clear() async => _box.clear();

  @override
  Future<List<HelpRequest>> nearby({
    double? latitude,
    double? longitude,
    double radiusMetres = 5000,
  }) async {
    final all = _readAll();
    if (latitude == null || longitude == null) return all;
    return all
        .where((r) => distanceBetween(
              latitude,
              longitude,
              r.latitude,
              r.longitude,
            ) <=
            radiusMetres)
        .toList();
  }
}

/// In-memory implementation used by tests.
class MemoryHelpRequestRepository implements HelpRequestRepository {
  final Map<String, HelpRequest> _store = {};
  final _controller = StreamController<List<HelpRequest>>.broadcast();

  List<HelpRequest> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<HelpRequest>> watchAll() {
    _controller.add(_readAll());
    return _controller.stream;
  }

  @override
  Future<List<HelpRequest>> getAll() async => _readAll();

  @override
  Future<HelpRequest?> getById(String requestId) async => _store[requestId];

  @override
  Future<void> save(HelpRequest request) async {
    _store[request.requestId] = request;
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> delete(String requestId) async {
    _store.remove(requestId);
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> clear() async {
    _store.clear();
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<List<HelpRequest>> nearby({
    double? latitude,
    double? longitude,
    double radiusMetres = 5000,
  }) async {
    final all = _readAll();
    if (latitude == null || longitude == null) return all;
    return all
        .where((r) => distanceBetween(
              latitude,
              longitude,
              r.latitude,
              r.longitude,
            ) <=
            radiusMetres)
        .toList();
  }

  void dispose() => _controller.close();
}
