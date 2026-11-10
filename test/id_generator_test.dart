/// Unit tests for the deterministic ID generator.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/core/utils/id_generator.dart';

void main() {
  final generator = IdGenerator();
  final fixed = DateTime.utc(2026, 9, 22, 12, 0, 0);

  test('deviceId matches the DEVICE-XXXXXXXX shape', () {
    final id = generator.deviceId();
    expect(id, matches(RegExp(r'^DEVICE-[0-9A-F]{8}$')));
  });

  test('teamId matches the TEAM-XXXXXX shape', () {
    final id = generator.teamId();
    expect(id, matches(RegExp(r'^TEAM-[0-9A-F]{6}$')));
    expect(id, matches(IdGenerator.teamIdPattern));
  });

  test('packetId matches the PKT-XXXXXXXX shape', () {
    final id = generator.packetId();
    expect(id, matches(RegExp(r'^PKT-[0-9A-F]{8}$')));
  });

  test('sosId embeds the provided date in UTC', () {
    final id = generator.sosId(at: fixed);
    expect(id, 'SOS-20260922-${id.substring(id.length - 6)}');
    expect(id, matches(IdGenerator.sosIdPattern));
  });

  test('sosId uses the current time when no date is supplied', () {
    final id = generator.sosId();
    expect(id, matches(IdGenerator.sosIdPattern));
  });

  test('ackId is derived deterministically from the SOS id', () {
    const sosId = 'SOS-20260922-ABCDEF';
    expect(generator.ackId(sosId), 'ACK-SOS-20260922-ABCDEF');
    expect(generator.ackId(sosId), matches(IdGenerator.ackIdPattern));
  });

  test('successive ids differ', () {
    final a = generator.sosId(at: fixed);
    final b = generator.sosId(at: fixed);
    expect(a, isNot(b));
  });

  test('the exposed patterns reject malformed ids', () {
    expect(IdGenerator.sosIdPattern.hasMatch('SOS-20260922'), isFalse);
    expect(IdGenerator.sosIdPattern.hasMatch('sos-20260922-ABCDEF'), isFalse);
    expect(IdGenerator.packetIdPattern.hasMatch('PKT-1234567'), isFalse);
    expect(IdGenerator.deviceIdPattern.hasMatch('DEVICE-GHIJ'), isFalse);
  });
}