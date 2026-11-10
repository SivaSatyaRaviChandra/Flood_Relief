/// Deterministic, injectable ID generation for SOSs, packets, ACKs, field
/// reports, help requests, shelters, contacts, alerts and device identities.
library;

import 'dart:math';

class IdGenerator {
  IdGenerator();
  final Random _random = Random.secure();

  String _hex(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16).toUpperCase());
    }
    return buffer.toString();
  }

  /// `YYYYMMDD` in UTC for the supplied (or current) instant.
  String _datePart(DateTime? at) {
    final time = (at ?? DateTime.now()).toUtc();
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// `DEVICE-XXXXXXXX`
  String deviceId() => 'DEVICE-${_hex(8)}';

  /// `PKT-XXXXXXXX`
  String packetId() => 'PKT-${_hex(8)}';

  /// `SOS-YYYYMMDD-XXXXXX`
  String sosId({DateTime? at}) => 'SOS-${_datePart(at)}-${_hex(6)}';

  /// `FLD-YYYYMMDD-XXXXXX` — a flood report.
  String floodReportId({DateTime? at}) => 'FLD-${_datePart(at)}-${_hex(6)}';

  /// `REQ-YYYYMMDD-XXXXXX` — a help request.
  String helpRequestId({DateTime? at}) => 'REQ-${_datePart(at)}-${_hex(6)}';

  /// `ALT-YYYYMMDD-XXXXXX` — an alert record.
  String alertId({DateTime? at}) => 'ALT-${_datePart(at)}-${_hex(6)}';

  /// `SHT-XXXXXX` — a shelter.
  String shelterId() => 'SHT-${_hex(6)}';

  /// `CON-XXXXXX` — an emergency contact.
  String contactId() => 'CON-${_hex(6)}';

  /// `TEAM-XXXXXX` — a rescue team.
  String teamId() => 'TEAM-${_hex(6)}';

  /// `ACK-<sosId>` — a deterministic ACK id for a given SOS.
  String ackId(String sosId) => 'ACK-$sosId';

  static final RegExp sosIdPattern = RegExp(r'^SOS-\d{8}-[0-9A-F]{6}$');
  static final RegExp packetIdPattern = RegExp(r'^PKT-[0-9A-F]{8}$');
  static final RegExp ackIdPattern = RegExp(r'^ACK-SOS-\d{8}-[0-9A-F]{6}$');
  static final RegExp deviceIdPattern = RegExp(r'^DEVICE-[0-9A-F]{8}$');
  static final RegExp floodReportIdPattern = RegExp(r'^FLD-\d{8}-[0-9A-F]{6}$');
  static final RegExp helpRequestIdPattern =
      RegExp(r'^REQ-\d{8}-[0-9A-F]{6}$');
  static final RegExp alertIdPattern = RegExp(r'^ALT-\d{8}-[0-9A-F]{6}$');
  static final RegExp shelterIdPattern = RegExp(r'^SHT-[0-9A-F]{6}$');
  static final RegExp contactIdPattern = RegExp(r'^CON-[0-9A-F]{6}$');
  static final RegExp teamIdPattern = RegExp(r'^TEAM-[0-9A-F]{6}$');
}
