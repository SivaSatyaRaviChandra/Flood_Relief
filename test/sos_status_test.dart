/// SOS status machine: allowed transitions, terminal state and code mapping.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/models/enums/sos_status.dart';

void main() {
  test('pending allows acknowledge and direct in-progress', () {
    expect(SosStatus.pending.canTransitionTo(SosStatus.acknowledged), isTrue);
    expect(SosStatus.pending.canTransitionTo(SosStatus.inProgress), isTrue);
    expect(SosStatus.pending.canTransitionTo(SosStatus.rescueAssigned), isFalse);
    expect(SosStatus.pending.canTransitionTo(SosStatus.resolved), isFalse);
  });

  test('acknowledged allows assign and in-progress', () {
    expect(SosStatus.acknowledged.canTransitionTo(SosStatus.rescueAssigned), isTrue);
    expect(SosStatus.acknowledged.canTransitionTo(SosStatus.inProgress), isTrue);
    expect(SosStatus.acknowledged.canTransitionTo(SosStatus.pending), isFalse);
  });

  test('rescueAssigned may only start the rescue', () {
    expect(SosStatus.rescueAssigned.canTransitionTo(SosStatus.inProgress), isTrue);
    expect(SosStatus.rescueAssigned.canTransitionTo(SosStatus.acknowledged), isFalse);
  });

  test('inProgress resolves; resolved is terminal', () {
    expect(SosStatus.inProgress.canTransitionTo(SosStatus.resolved), isTrue);
    expect(SosStatus.resolved.allowedTransitions, isEmpty);
    expect(SosStatus.resolved.canTransitionTo(SosStatus.pending), isFalse);
  });

  test('isActive is false only for resolved', () {
    for (final status in SosStatus.values) {
      expect(status.isActive, status != SosStatus.resolved,
          reason: '${status.name} active flag');
    }
  });

  test('fromCode round-trips every status and rejects junk', () {
    for (final status in SosStatus.values) {
      expect(SosStatus.fromCode(status.code), status);
    }
    expect(SosStatus.fromCode('NOPE'), isNull);
    expect(SosStatus.fromCode(null), isNull);
  });
}