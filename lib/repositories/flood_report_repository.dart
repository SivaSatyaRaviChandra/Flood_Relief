/// Flood report persistence.
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/errors/app_error.dart';
import '../core/utils/geo.dart';
import '../models/flood_report.dart';
import 'hive_stream_support.dart';

abstract class FloodReportRepository {
  Stream<List<FloodReport>> watchAll();
  Future<List<FloodReport>> getAll();
  Future<FloodReport?> getById(String reportId);
  Future<void> save(FloodReport report);
  Future<void> delete(String reportId);
  Future<void> clear();

  /// Reports filed at or after [since]. When a position is supplied, only
  /// reports within [radiusMetres] of it are returned.
  Future<List<FloodReport>> nearby({
    required DateTime since,
    double? latitude,
    double? longitude,
    double radiusMetres = 5000,
  });
}

class HiveFloodReportRepository implements FloodReportRepository {
  HiveFloodReportRepository(this._box);

  final Box _box;

  List<FloodReport> _readAll() {
    final list = <FloodReport>[];
    for (final value in _box.values) {
      list.add(FloodReport.fromMap(value));
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<FloodReport>> watchAll() => watchBoxSnapshot(_box, _readAll);

  @override
  Future<List<FloodReport>> getAll() async => _readAll();

  @override
  Future<FloodReport?> getById(String reportId) async {
    final value = _box.get(reportId);
    return value == null ? null : FloodReport.fromMap(value);
  }

  @override
  Future<void> save(FloodReport report) async {
    try {
      await _box.put(report.reportId, report.toMap());
    } catch (e) {
      throw DatabaseError(
        'Could not store the flood report on this device.',
        cause: e,
      );
    }
  }

  @override
  Future<void> delete(String reportId) async => _box.delete(reportId);

  @override
  Future<void> clear() async => _box.clear();

  @override
  Future<List<FloodReport>> nearby({
    required DateTime since,
    double? latitude,
    double? longitude,
    double radiusMetres = 5000,
  }) async {
    final all = _readAll().where((r) => !r.timestamp.isBefore(since)).toList();
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
class MemoryFloodReportRepository implements FloodReportRepository {
  final Map<String, FloodReport> _store = {};
  final _controller = StreamController<List<FloodReport>>.broadcast();

  List<FloodReport> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<FloodReport>> watchAll() {
    _controller.add(_readAll());
    return _controller.stream;
  }

  @override
  Future<List<FloodReport>> getAll() async => _readAll();

  @override
  Future<FloodReport?> getById(String reportId) async => _store[reportId];

  @override
  Future<void> save(FloodReport report) async {
    _store[report.reportId] = report;
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> delete(String reportId) async {
    _store.remove(reportId);
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> clear() async {
    _store.clear();
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<List<FloodReport>> nearby({
    required DateTime since,
    double? latitude,
    double? longitude,
    double radiusMetres = 5000,
  }) async {
    final all = _readAll().where((r) => !r.timestamp.isBefore(since)).toList();
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
