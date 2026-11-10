/// Typed application errors and the mapping to user-facing messages.
///
/// The UI layer must never display stack traces. Every failure that can reach
/// a user is represented by an [AppError] carrying a human readable message.
library;

/// Categories of failure the application understands.
enum AppErrorKind {
  locationUnavailable,
  permissionDenied,
  permissionPermanentlyDenied,
  gpsDisabled,
  locationTimeout,
  bleDisabled,
  blePermissionDenied,
  connectionFailure,
  packetTimeout,
  duplicatePacket,
  invalidPacket,
  replayRejected,
  databaseFailure,
  invalidForm,
  speechRecognitionFailure,
  notFound,
  unknown,
}

/// A typed error with a user-facing message.
class AppError implements Exception {
  const AppError(this.kind, this.message, {this.cause, this.retriable = false});

  final AppErrorKind kind;
  final String message;
  final Object? cause;
  final bool retriable;

  /// A short label used in chips/banners.
  String get label => _labels[kind] ?? 'Error';

  static const Map<AppErrorKind, String> _labels = {
    AppErrorKind.locationUnavailable: 'Location unavailable',
    AppErrorKind.permissionDenied: 'Location permission denied',
    AppErrorKind.permissionPermanentlyDenied: 'Location permission permanently denied',
    AppErrorKind.gpsDisabled: 'GPS disabled',
    AppErrorKind.locationTimeout: 'Location request timed out',
    AppErrorKind.bleDisabled: 'Bluetooth disabled',
    AppErrorKind.blePermissionDenied: 'Bluetooth permission denied',
    AppErrorKind.connectionFailure: 'Connection failed',
    AppErrorKind.packetTimeout: 'Packet timed out',
    AppErrorKind.duplicatePacket: 'Duplicate packet',
    AppErrorKind.invalidPacket: 'Invalid packet',
    AppErrorKind.replayRejected: 'Replay rejected',
    AppErrorKind.databaseFailure: 'Storage error',
    AppErrorKind.invalidForm: 'Invalid input',
    AppErrorKind.speechRecognitionFailure: 'Speech recognition failed',
    AppErrorKind.notFound: 'Not found',
    AppErrorKind.unknown: 'Unexpected error',
  };

  @override
  String toString() => 'AppError($kind): $message';
}

/// Raised when a SOS/ACK status transition is not allowed.
class InvalidStatusTransitionError implements Exception {
  const InvalidStatusTransitionError(this.from, this.to);
  final String from;
  final String to;

  @override
  String toString() =>
      'InvalidStatusTransitionError: cannot move $from -> $to';
}

/// Raised when a form/dto fails validation.
class InvalidFormError implements Exception {
  const InvalidFormError(this.errors);
  final List<String> errors;

  String get message => errors.join('\n');

  @override
  String toString() => 'InvalidFormError: $message';
}

/// Raised when a BLE packet fails validation.
class PacketValidationError implements Exception {
  const PacketValidationError(this.reason, {this.packetId});
  final String reason;
  final String? packetId;

  @override
  String toString() => 'PacketValidationError: $reason';
}

/// Raised by repositories when persistence fails.
class DatabaseError extends AppError {
  DatabaseError(String message, {Object? cause})
      : super(AppErrorKind.databaseFailure, message, cause: cause);
}