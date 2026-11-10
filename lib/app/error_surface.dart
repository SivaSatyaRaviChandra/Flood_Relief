/// Global error surface.
///
/// Two jobs, both aimed at the "silent white screen" failure mode:
///
///  1. [ErrorLog] keeps a bounded, in-memory record of every framework and
///     asynchronous error. When a widget throws during build, the default
///     `ErrorWidget` renders a bare red box in debug and a *blank grey box* in
///     release — a user cannot read it and a developer cannot copy it.
///     [readableErrorBuilder] renders the error text and records it, and
///     Settings → Diagnostics shows the log.
///
///  2. [installGlobalErrorHandlers] routes both `FlutterError.onError` (build /
///     layout / async-in-widget errors) and `PlatformDispatcher.onError`
///     (unawaited-future and isolate errors that never touch a widget) into
///     the same log instead of letting them disappear.
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';

/// One recorded failure.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.at,
    required this.message,
    required this.stackTrace,
    required this.source,
  });

  final DateTime at;
  final String message;
  final String stackTrace;

  /// Where the error came from: `framework`, `async`, or a screen's own label.
  final String source;

  /// First line of [message] plus the first frame — enough to identify the
  /// failure without dumping a whole stack trace into a ListTile.
  String get summary {
    final firstMessageLine = message.split('\n').first.trim();
    final firstFrame = stackTrace.split('\n').first.trim();
    if (firstFrame.isEmpty || firstFrame == firstMessageLine) {
      return firstMessageLine;
    }
    return '$firstMessageLine\n$firstFrame';
  }
}

/// Bounded in-memory error log. Oldest entries are dropped once
/// [Limits.maxErrorLogEntries] is reached, so a crash loop cannot grow it
/// without limit.
class ErrorLog extends ChangeNotifier {
  ErrorLog({DateTime Function()? now, this.capacity = Limits.maxErrorLogEntries})
      : _now = now ?? _defaultNow;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final DateTime Function() _now;

  /// Maximum retained entries. Older entries are dropped beyond this.
  final int capacity;

  final List<ErrorLogEntry> _entries = [];

  /// Newest first.
  List<ErrorLogEntry> get entries => List.unmodifiable(_entries.reversed);

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  void record(
    Object error,
    StackTrace stackTrace, {
    String source = 'framework',
  }) {
    _entries.add(
      ErrorLogEntry(
        at: _now().toUtc(),
        message: describe(error),
        stackTrace: '$stackTrace',
        source: source,
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

/// User-facing one-liner for any throwable.
///
/// [AppError] already carries a message written for humans, so it is used
/// verbatim. Anything else is reduced to its own text so a raw exception never
/// leaks internal wording into the UI.
String describe(Object error) {
  if (error is AppError) return error.message;
  if (error is InvalidFormError) return error.message;
  final text = error.toString().trim();
  if (text.isEmpty) return error.runtimeType.toString();
  return text;
}

/// The process-wide log.
///
/// A plain global rather than a Riverpod provider: [readableErrorBuilder] is
/// invoked by the framework for a widget that failed to build, and reading a
/// provider from that context is exactly the kind of thing that can itself
/// throw. The UI reads it through `errorLogProvider`, which returns this
/// instance.
final ErrorLog errorLog = ErrorLog();

/// The [ErrorWidget.builder] installed for the whole app.
///
/// Invoked by the framework for the *one* widget whose `build` threw, in a tree
/// the docs describe as fragile — so this returns a plain, layout-tolerant
/// box and nothing that can itself fail. It deliberately does **not** build a
/// `Scaffold` or call `Navigator`: [ErrorWidgetBuilder] receives
/// [FlutterErrorDetails], which carries no [BuildContext], so there is no
/// navigator to pop. The user gets a readable message and the back gesture
/// still works, because the surrounding route is untouched.
///
/// The default builder in a release build is a bare grey box — that *is* the
/// silent white screen this app must not have. Replacing it is the fix; the
/// same failure is also recorded in [errorLog] for Settings → Diagnostics.
Widget readableErrorBuilder(FlutterErrorDetails details) {
  final message = describe(details.exception);
  errorLog.record(
    details.exception,
    details.stack ?? StackTrace.current,
    source: 'widget build',
  );

  // No Scaffold / Navigator / InkWell: see the doc comment above. Everything
  // here is a `RenderBox` that tolerates any incoming constraint.
  return ColoredBox(
    color: const Color(0xFFFDECEA),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE57373)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This part of the screen could not be drawn. Your data is '
                'still on this device.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8E0000),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF8E0000),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Installs [readableErrorBuilder] as the process-wide [ErrorWidget.builder].
///
/// Called once by `main` and by the test harness. Kept separate from
/// [installGlobalErrorHandlers] because it mutates a static on
/// `ErrorWidget` rather than installing callbacks.
void installReadableErrorWidget() {
  ErrorWidget.builder = readableErrorBuilder;
}

/// Installs the process-wide handlers.
///
/// [onReport] receives every error after it is logged, so `main` can also
/// print to the console in debug builds.
void installGlobalErrorHandlers({
  required ErrorLog log,
  void Function(Object error, StackTrace stackTrace)? onReport,
}) {
  final previousOnError = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    log.record(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'framework',
    );
    onReport?.call(
      details.exception,
      details.stack ?? StackTrace.current,
    );
    // Keep the default console dump: it is the fastest way to see the error
    // with `flutter run`, and `previousOnError` is the same function in
    // practice, so calling it preserves existing behaviour.
    previousOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    log.record(error, stack, source: 'async');
    onReport?.call(error, stack);
    // Returning true marks the error as handled: without this, an unawaited
    // future error terminates the isolate and the app freezes on whatever was
    // last drawn — a white screen with no explanation.
    return true;
  };
}
