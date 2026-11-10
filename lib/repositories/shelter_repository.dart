/// Shelter / safe-location persistence.
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/errors/app_error.dart';
import '../core/utils/cast.dart';
import '../core/utils/geo.dart';
import '../models/shelter.dart';
import 'hive_stream_support.dart';

abstract class ShelterRepository {
  Stream<List<Shelter>> watchAll();
  Future<List<Shelter>> getAll();
  Future<Shelter?> getById(String shelterId);
  Future<void> save(Shelter shelter);
  Future<void> delete(String shelterId);
  Future<void> clear();

  /// Shelters sorted by distance from the supplied position. Shelters without
  /// coordinates are returned last, in name order, so nothing is hidden.
  Future<List<({Shelter shelter, double? distanceMetres})>> sortedByDistance({
    double? latitude,
    double? longitude,
  });
}

class HiveShelterRepository implements ShelterRepository {
  HiveShelterRepository(this._box);

  final Box _box;

  List<Shelter> _readAll() {
    final list = <Shelter>[];
    for (final value in _box.values) {
      list.add(Shelter.fromMap(value));
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Stream<List<Shelter>> watchAll() => watchBoxSnapshot(_box, _readAll);

  @override
  Future<List<Shelter>> getAll() async => _readAll();

  @override
  Future<Shelter?> getById(String shelterId) async {
    final value = _box.get(shelterId);
    return value == null ? null : Shelter.fromMap(value);
  }

  @override
  Future<void> save(Shelter shelter) async {
    try {
      await _box.put(shelter.shelterId, shelter.toMap());
    } catch (e) {
      throw DatabaseError('Could not store the shelter record.', cause: e);
    }
  }

  @override
  Future<void> delete(String shelterId) async => _box.delete(shelterId);

  @override
  Future<void> clear() async => _box.clear();

  @override
  Future<List<({Shelter shelter, double? distanceMetres})>> sortedByDistance({
    double? latitude,
    double? longitude,
  }) async {
    final all = _readAll();
    final located = all.where((s) => s.hasCoordinates).toList();
    final unlocated = all.where((s) => !s.hasCoordinates).toList();

    final positioned = <({Shelter shelter, double? distanceMetres})>[];
    for (final shelter in located) {
      final distance = (latitude == null || longitude == null)
          ? null
          : distanceBetween(
              latitude,
              longitude,
              shelter.latitude!,
              shelter.longitude!,
            );
      positioned.add((shelter: shelter, distanceMetres: distance));
    }
    positioned.sort((a, b) {
      final da = a.distanceMetres;
      final db = b.distanceMetres;
      if (da == null && db == null) {
        return a.shelter.name.compareTo(b.shelter.name);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return [
      ...positioned,
      ...unlocated.map((s) => (shelter: s, distanceMetres: null)),
    ];
  }
}

/// In-memory implementation used by tests.
class MemoryShelterRepository implements ShelterRepository {
  final Map<String, Shelter> _store = {};
  final _controller = StreamController<List<Shelter>>.broadcast();

  List<Shelter> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Stream<List<Shelter>> watchAll() {
    _controller.add(_readAll());
    return _controller.stream;
  }

  @override
  Future<List<Shelter>> getAll() async => _readAll();

  @override
  Future<Shelter?> getById(String shelterId) async => _store[shelterId];

  @override
  Future<void> save(Shelter shelter) async {
    _store[shelter.shelterId] = shelter;
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> delete(String shelterId) async {
    _store.remove(shelterId);
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<void> clear() async {
    _store.clear();
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Future<List<({Shelter shelter, double? distanceMetres})>> sortedByDistance({
    double? latitude,
    double? longitude,
  }) {
    final all = _readAll();
    final located = all.where((s) => s.hasCoordinates).toList();
    final unlocated = all.where((s) => !s.hasCoordinates).toList();
    final positioned = <({Shelter shelter, double? distanceMetres})>[];
    for (final shelter in located) {
      final distance = (latitude == null || longitude == null)
          ? null
          : distanceBetween(
              latitude,
              longitude,
              shelter.latitude!,
              shelter.longitude!,
            );
      positioned.add((shelter: shelter, distanceMetres: distance));
    }
    positioned.sort((a, b) {
      final da = a.distanceMetres;
      final db = b.distanceMetres;
      if (da == null && db == null) {
        return a.shelter.name.compareTo(b.shelter.name);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return Future.value([
      ...positioned,
      ...unlocated.map((s) => (shelter: s, distanceMetres: null)),
    ]);
  }

  void dispose() => _controller.close();
}

/// Parses an occupancy string such as `"120/300"` into `(occupied, capacity)`.
///
/// Used when importing shelter data typed by hand.
({int occupied, int capacity})? parseOccupancy(String raw) {
  final parts = raw.split('/');
  if (parts.length != 2) return null;
  final occupied = asInt(parts[0].trim());
  final capacity = asInt(parts[1].trim());
  if (occupied == null || capacity == null) return null;
  if (capacity < 0 || occupied < 0) return null;
  return (occupied: occupied, capacity: capacity);
}
