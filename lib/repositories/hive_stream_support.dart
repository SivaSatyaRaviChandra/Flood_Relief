/// Shared Hive plumbing for repositories.
///
/// Every repository needs the same behaviour: a broadcast stream that emits
/// the *current* snapshot when the first listener attaches and then again on
/// every box write. Hive's own `Box.watch()` only fires on modification, and a
/// broadcast controller drops events added before it has a listener, so a
/// naive implementation renders an empty list forever. This helper centralises
/// the pattern (it was previously copy-pasted in four repositories).
library;

import 'dart:async';

import 'package:hive/hive.dart';

/// Emits [readAll]'s result on listen and on every change to [box].
Stream<List<T>> watchBoxSnapshot<T>(
  Box box,
  List<T> Function() readAll, {
  String? key,
}) {
  late final StreamController<List<T>> controller;
  StreamSubscription<BoxEvent>? subscription;
  controller = StreamController<List<T>>.broadcast(
    onListen: () {
      controller.add(readAll());
      subscription = box.watch(key: key).listen((_) {
        if (!controller.isClosed) controller.add(readAll());
      });
    },
    onCancel: () => subscription?.cancel(),
  );
  return controller.stream;
}

/// Emits an event on listen and on every change to [box].
Stream<void> watchBoxChanges(
  Box box, {
  String? key,
}) {
  late final StreamController<void> controller;
  StreamSubscription<BoxEvent>? subscription;
  controller = StreamController<void>.broadcast(
    onListen: () {
      controller.add(null);
      subscription = box.watch(key: key).listen((_) {
        if (!controller.isClosed) controller.add(null);
      });
    },
    onCancel: () => subscription?.cancel(),
  );
  return controller.stream;
}
