/// Key-value settings persistence (demo mode, onboarding state, ...).
library;

import 'package:hive/hive.dart';

import '../core/utils/cast.dart';

abstract class SettingsRepository {
  Future<bool> getBool(String key, {bool fallback = false});
  Future<void> setBool(String key, bool value);
  Future<String> getString(String key, {String fallback = ''});
  Future<void> setString(String key, String value);
}

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  final Box _box;

  @override
  Future<bool> getBool(String key, {bool fallback = false}) async =>
      asBool(_box.get(key), fallback: fallback);

  @override
  Future<void> setBool(String key, bool value) async {
    await _box.put(key, value);
  }

  @override
  Future<String> getString(String key, {String fallback = ''}) async {
    final value = _box.get(key);
    return value == null ? fallback : value.toString();
  }

  @override
  Future<void> setString(String key, String value) async {
    await _box.put(key, value);
  }
}

/// In-memory implementation used by tests.
///
/// Every other repository in this package ships a `Memory*` twin for the same
/// reason: Hive box writes go through real file I/O, which never completes
/// inside `testWidgets`' fake-async zone. Without this, any screen that persists
/// a setting (onboarding, the link toggles, the last known position) would hang
/// mid-action in a widget test even though the app itself is fine.
class MemorySettingsRepository implements SettingsRepository {
  final Map<String, Object> _store = {};

  @override
  Future<bool> getBool(String key, {bool fallback = false}) async =>
      asBool(_store[key], fallback: fallback);

  @override
  Future<void> setBool(String key, bool value) async {
    _store[key] = value;
  }

  @override
  Future<String> getString(String key, {String fallback = ''}) async {
    final value = _store[key];
    return value == null ? fallback : value.toString();
  }

  @override
  Future<void> setString(String key, String value) async {
    _store[key] = value;
  }

  /// Test-only view of what was written, so a test can assert on it.
  Object? operator [](String key) => _store[key];
}