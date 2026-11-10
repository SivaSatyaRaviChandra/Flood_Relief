/// Emergency contact persistence.
///
/// The contact list is user-managed and starts empty. This class therefore
/// ships **no** default rows: inventing government hotline numbers would be
/// unsafe (a wrong number during a flood is worse than none).
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/errors/app_error.dart';
import '../models/emergency_contact.dart';
import 'hive_stream_support.dart';

abstract class EmergencyContactRepository {
  /// Sorted so the primary contact comes first, then alphabetical.
  Stream<List<EmergencyContact>> watchAll();

  Future<List<EmergencyContact>> getAll();
  Future<EmergencyContact?> getById(String contactId);

  /// Saves [contact]. When it is marked [EmergencyContact.isPrimary] every
  /// other contact is demoted first, so at most one primary ever exists.
  Future<void> save(EmergencyContact contact);

  Future<void> delete(String contactId);
  Future<void> clear();

  /// Demotes every contact except [contactId].
  Future<void> demoteAllExcept(String contactId);
}

class HiveEmergencyContactRepository implements EmergencyContactRepository {
  HiveEmergencyContactRepository(this._box);

  final Box _box;

  List<EmergencyContact> _readAll() {
    final list = <EmergencyContact>[];
    for (final value in _box.values) {
      list.add(EmergencyContact.fromMap(value));
    }
    list.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  Stream<List<EmergencyContact>> watchAll() => watchBoxSnapshot(_box, _readAll);

  @override
  Future<List<EmergencyContact>> getAll() async => _readAll();

  @override
  Future<EmergencyContact?> getById(String contactId) async {
    final value = _box.get(contactId);
    return value == null ? null : EmergencyContact.fromMap(value);
  }

  @override
  Future<void> save(EmergencyContact contact) async {
    try {
      if (contact.isPrimary) await demoteAllExcept(contact.contactId);
      await _box.put(contact.contactId, contact.toMap());
    } catch (e) {
      throw DatabaseError(
        'Could not store the contact on this device.',
        cause: e,
      );
    }
  }

  @override
  Future<void> delete(String contactId) => _box.delete(contactId);

  @override
  Future<void> clear() => _box.clear();

  @override
  Future<void> demoteAllExcept(String contactId) async {
    for (final value in _box.values) {
      final existing = EmergencyContact.fromMap(value);
      if (existing.contactId == contactId) continue;
      if (!existing.isPrimary) continue;
      await _box.put(
        existing.contactId,
        existing.copyWith(isPrimary: false).toMap(),
      );
    }
  }
}

/// In-memory implementation used by tests.
class MemoryEmergencyContactRepository implements EmergencyContactRepository {
  final Map<String, EmergencyContact> _store = {};
  final _controller = StreamController<List<EmergencyContact>>.broadcast();

  List<EmergencyContact> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Stream<List<EmergencyContact>> watchAll() {
    _emit();
    return _controller.stream;
  }

  @override
  Future<List<EmergencyContact>> getAll() async => _readAll();

  @override
  Future<EmergencyContact?> getById(String contactId) async =>
      _store[contactId];

  @override
  Future<void> save(EmergencyContact contact) async {
    if (contact.isPrimary) await demoteAllExcept(contact.contactId);
    _store[contact.contactId] = contact;
    _emit();
  }

  @override
  Future<void> delete(String contactId) async {
    _store.remove(contactId);
    _emit();
  }

  @override
  Future<void> clear() async {
    _store.clear();
    _emit();
  }

  @override
  Future<void> demoteAllExcept(String contactId) async {
    var changed = false;
    for (final entry in _store.entries.toList()) {
      if (entry.key == contactId) continue;
      if (!entry.value.isPrimary) continue;
      _store[entry.key] = entry.value.copyWith(isPrimary: false);
      changed = true;
    }
    if (changed) _emit();
  }

  void dispose() => _controller.close();
}
