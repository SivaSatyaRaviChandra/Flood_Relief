/// SOS request serialization: Hive map round-trip and REST JSON shape.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/enums/sos_status.dart';
import 'package:flood_relief/models/people_info.dart';
import 'package:flood_relief/models/sos_request.dart';
import 'package:flood_relief/models/status_history.dart';

SosRequest _sample() {
  final at = DateTime.utc(2026, 9, 22, 12, 0, 0);
  return SosRequest(
    sosId: 'SOS-20260922-ABC123',
    userId: 'USER-1',
    timestamp: at,
    latitude: 17.7,
    longitude: 83.3,
    accuracy: 12.0,
    people: const PeopleInfo(
      totalPeople: 8,
      childrenCount: 2,
      elderlyCount: 1,
      pregnantWomenCount: 0,
      specialAssistanceCount: 0,
    ),
    emergencyType: EmergencyType.rescueRequired,
    description: 'Water rising, people trapped.',
    priority: SosPriority.high,
    status: SosStatus.acknowledged,
    assignedTeamId: 'TEAM-001',
    originDeviceId: 'DEVICE-ABCD1234',
    hopCount: 2,
    acknowledged: true,
    acknowledgedAt: at.add(const Duration(minutes: 2)),
    statusHistory: [
      StatusHistoryEntry(
        previousStatus: SosStatus.pending,
        newStatus: SosStatus.acknowledged,
        timestamp: at.add(const Duration(minutes: 2)),
        teamId: 'RESCUE-NODE',
        note: 'ACK received.',
      ),
    ],
  );
}

void main() {
  test('toMap/fromMap round-trips every field', () {
    final request = _sample();
    final restored = SosRequest.fromMap(request.toMap());

    expect(restored.sosId, request.sosId);
    expect(restored.userId, request.userId);
    expect(restored.timestamp, request.timestamp);
    expect(restored.latitude, request.latitude);
    expect(restored.longitude, request.longitude);
    expect(restored.accuracy, request.accuracy);
    expect(restored.people.totalPeople, request.people.totalPeople);
    expect(restored.people.childrenCount, request.people.childrenCount);
    expect(restored.emergencyType, request.emergencyType);
    expect(restored.description, request.description);
    expect(restored.priority, request.priority);
    expect(restored.status, request.status);
    expect(restored.assignedTeamId, request.assignedTeamId);
    expect(restored.originDeviceId, request.originDeviceId);
    expect(restored.hopCount, request.hopCount);
    expect(restored.acknowledged, request.acknowledged);
    expect(restored.acknowledgedAt, request.acknowledgedAt);
    expect(restored.statusHistory, hasLength(1));
    expect(restored.statusHistory.first.previousStatus, SosStatus.pending);
    expect(restored.statusHistory.first.newStatus, SosStatus.acknowledged);
    expect(restored.statusHistory.first.teamId, 'RESCUE-NODE');
  });

  test('toJson uses the backend schema', () {
    final json = _sample().toJson();
    expect(json['sos_id'], 'SOS-20260922-ABC123');
    expect(json['user_id'], 'USER-1');
    expect(json['origin_device_id'], 'DEVICE-ABCD1234');
    expect(json['latitude'], 17.7);
    expect(json['total_people'], 8);
    expect(json['children_count'], 2);
    expect(json['emergency_type'], 'RESCUE_REQUIRED');
    expect(json['priority'], 'HIGH');
    expect(json['status'], 'ACKNOWLEDGED');
    expect(json['hop_count'], 2);
    expect(json['acknowledged'], isTrue);
    expect(json.containsKey('status_history'), isFalse);
  });

  test('copyWith supports clearing optional fields', () {
    final request = _sample();
    final cleared = request.copyWith(
      accuracy: null,
      assignedTeamId: null,
      acknowledgedAt: null,
      clearAccuracy: true,
      clearAssignedTeam: true,
      clearAcknowledgedAt: true,
    );
    expect(cleared.accuracy, isNull);
    expect(cleared.assignedTeamId, isNull);
    expect(cleared.acknowledgedAt, isNull);
    expect(cleared.statusHistory, hasLength(1));
  });

  test('fromMap falls back to safe defaults for missing data', () {
    final restored = SosRequest.fromMap(const {});
    expect(restored.userId, '');
    expect(restored.emergencyType, EmergencyType.other);
    expect(restored.priority, SosPriority.low);
    expect(restored.status, SosStatus.pending);
    expect(restored.originDeviceId, 'DEVICE-UNKNOWN');
    expect(restored.hopCount, 0);
  });
}