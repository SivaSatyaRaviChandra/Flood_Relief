/// Alert persistence.
///
/// Alerts are derived from real local data (see `services/alert_service.dart`)
/// or written by a rescue operator; they are never invented. Read/unread state
/// is persisted so it survives a restart.
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../models/alert_record.dart';
import 'hive_stream_support.dart';

abstract class AlertRepository {
  Stream<List<AlertRecord>> watchAll();

  /// Newest first.
  Future<List<AlertRecord>> getAll();

  Future<AlertRecord?> getById(String alertId);
  Future<void> save(AlertRecord alert);
  Future<void> delete(String alertId);

  /// Marks one alert as read. No-op when already read.
  Future<void> markRead(String alertId);

  /// Marks every alert as read. Returns how many changed.
  Future<int> markAllRead();

  /// How many alerts are still unread.
  Future<int> unreadCount();

  /// Drops the oldest entries beyond [Limits.maxStoredAlerts].
  Future<int> prune();

  Future<void> clear();
}

class HiveAlertRepository implements AlertRepository {
  HiveAlertRepository(this._box);

  final Box _box;

  List<AlertRecord> _readAll() {
    final list = <AlertRecord>[];
    for (final value in _box.values) {
      list.add(AlertRecord.fromMap(value));
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<AlertRecord>> watchAll() => watchBoxSnapshot(_box, _readAll);

  @override
  Future<List<AlertRecord>> getAll() async => _readAll();

  @override
  Future<AlertRecord?> getById(String alertId) async {
    final value = _box.get(alertId);
    return value == null ? null : AlertRecord.fromMap(value);
  }

  @override
  Future<void> save(AlertRecord alert) async {
    try {
      await _box.put(alert.alertId, alert.toMap());
    } catch (e) {
      throw DatabaseError(
        'Could not store the alert on this device.',
        cause: e,
      );
    }
  }

  @override
  Future<void> delete(String alertId) => _box.delete(alertId);

  @override
  Future<void> markRead(String alertId) async {
    final existing = await getById(alertId);
    if (existing == null || existing.read) return;
    await save(existing.copyWith(read: true));
  }

  @override
  Future<int> markAllRead() async {
    final unread = _readAll().where((a) => !a.read).toList();
    for (final alert in unread) {
      await save(alert.copyWith(read: true));
    }
    return unread.length;
  }

  @override
  Future<int> unreadCount() async => _readAll().where((a) => !a.read).length;

  @override
  Future<int> prune() async {
    final all = _readAll();
    if (all.length <= Limits.maxStoredAlerts) return 0;
    // `all` is newest-first, so everything past the cap is the oldest.
    final doomed = all.sublist(Limits.maxStoredAlerts);
    for (final alert in doomed) {
      await _box.delete(alert.alertId);
    }
    return doomed.length;
  }

  @override
  Future<void> clear() => _box.clear();
}

/// In-memory implementation used by tests.
class MemoryAlertRepository implements AlertRepository {
  final Map<String, AlertRecord> _store = {};
  final _controller = StreamController<List<AlertRecord>>.broadcast();

  List<AlertRecord> _readAll() {
    final list = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  @override
  Stream<List<AlertRecord>> watchAll() {
    _emit();
    return _controller.stream;
  }

  @override
  Future<List<AlertRecord>> getAll() async => _readAll();

  @override
  Future<AlertRecord?> getById(String alertId) async => _store[alertId];

  @override
  Future<void> save(AlertRecord alert) async {
    _store[alert.alertId] = alert;
    _emit();
  }

  @override
  Future<void> delete(String alertId) async {
    _store.remove(alertId);
    _emit();
  }

  @override
  Future<void> markRead(String alertId) async {
    final existing = _store[alertId];
    if (existing == null || existing.read) return;
    await save(existing.copyWith(read: true));
  }

  @override
  Future<int> markAllRead() async {
    final unread = _readAll().where((a) => !a.read).toList();
    for (final alert in unread) {
      _store[alert.alertId] = alert.copyWith(read: true);
    }
    _emit();
    return unread.length;
  }

  @override
  Future<int> unreadCount() async => _readAll().where((a) => !a.read).length;

  @override
  Future<int> prune() async {
    final all = _readAll();
    if (all.length <= Limits.maxStoredAlerts) return 0;
    final doomed = all.sublist(Limits.maxStoredAlerts);
    for (final alert in doomed) {
      _store.remove(alert.alertId);
    }
    _emit();
    return doomed.length;
  }

  @override
  Future<void> clear() async {
    _store.clear();
    _emit();
  }

  void dispose() => _controller.close();
}

/// A stable key describing "one alert per (source, related record, topic)".
///
/// Used so re-deriving alerts after every local change cannot produce an
/// unbounded duplicate feed: the same SOS reaching the same status twice, or
/// the same critical report being seen again, produces the same key.
String alertDedupeKey({
  required AlertSource source,
  required String topic,
  String? relatedId,
}) => '$source/$topic/${relatedId ?? '-'}';

/// The first occurrence of [dedupeKey] in [alerts], or null.
///
/// Alerts arrive newest-first, so this finds the original that must keep its
/// read/unread state instead of being duplicated.
AlertRecord? findAlertWithKey(List<AlertRecord> alerts, String dedupeKey) {
  for (final alert in alerts) {
    if (alert.dedupeKey == dedupeKey) return alert;
  }
  return null;
}
