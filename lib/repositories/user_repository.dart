/// Persists the local application user (affected user or rescue operator).
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../models/app_user.dart';

abstract class UserRepository {
  Future<AppUser?> currentUser();
  Future<void> saveUser(AppUser user);
  Future<void> clear();
  Stream<AppUser?> watchUser();
}

class HiveUserRepository implements UserRepository {
  HiveUserRepository(this._box);

  final Box _box;

  static const _key = 'currentUser';

  @override
  Future<AppUser?> currentUser() async {
    final value = _box.get(_key);
    return value == null ? null : AppUser.fromMap(value);
  }

  @override
  Future<void> saveUser(AppUser user) async {
    await _box.put(_key, user.toMap());
  }

  @override
  Future<void> clear() async {
    await _box.delete(_key);
  }

  @override
  Stream<AppUser?> watchUser() {
    // Emit the current user from `onListen`; broadcast streams discard events
    // added before a listener attaches and `Box.watch(key:)` only fires on
    // writes.
    late final StreamController<AppUser?> controller;
    StreamSubscription<BoxEvent>? sub;
    controller = StreamController<AppUser?>.broadcast(
      onListen: () {
        controller.add(_read());
        sub = _box.watch(key: _key).listen((_) {
          if (!controller.isClosed) controller.add(_read());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  AppUser? _read() {
    final value = _box.get(_key);
    return value == null ? null : AppUser.fromMap(value);
  }
}