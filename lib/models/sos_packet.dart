/// BLE packet model.
///
/// Two packet kinds exist:
/// * [SosPacketMessage] — a structured SOS broadcast;
/// * [AckPacketMessage] — an acknowledgement for a previously sent SOS.
///
/// All timestamps are UTC ISO-8601 strings in the serialized form.
library;

import '../core/utils/time_format.dart';
import 'enums/emergency_type.dart';
import 'enums/sos_priority.dart';
import 'people_info.dart';

sealed class BlePacketMessage {
  const BlePacketMessage({
    required this.packetId,
    required this.sosId,
    required this.originDeviceId,
    required this.senderDeviceId,
    required this.hopCount,
    required this.ttl,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  final String packetId;
  final String sosId;

  /// The device that authored this packet (origin of the SOS for SOS
  /// packets, the acknowledging device for ACK packets).
  final String originDeviceId;

  /// The device that most recently forwarded this packet.
  final String senderDeviceId;

  final int hopCount;
  final int ttl;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracy;

  BlePacketMessage copyWith({
    String? senderDeviceId,
    int? hopCount,
    int? ttl,
  });

  Map<String, dynamic> toMap();
}

class SosPacketMessage extends BlePacketMessage {
  const SosPacketMessage({
    required super.packetId,
    required super.sosId,
    required super.originDeviceId,
    required super.senderDeviceId,
    required super.hopCount,
    required super.ttl,
    required super.timestamp,
    required super.latitude,
    required super.longitude,
    super.accuracy,
    required this.totalPeople,
    required this.childrenCount,
    required this.elderlyCount,
    required this.pregnantWomenCount,
    required this.specialAssistanceCount,
    required this.emergencyType,
    required this.description,
    required this.priority,
  });

  final int totalPeople;
  final int childrenCount;
  final int elderlyCount;
  final int pregnantWomenCount;
  final int specialAssistanceCount;
  final EmergencyType emergencyType;
  final String description;
  final SosPriority priority;

  PeopleInfo get people => PeopleInfo(
        totalPeople: totalPeople,
        childrenCount: childrenCount,
        elderlyCount: elderlyCount,
        pregnantWomenCount: pregnantWomenCount,
        specialAssistanceCount: specialAssistanceCount,
      );

  @override
  SosPacketMessage copyWith({
    String? senderDeviceId,
    int? hopCount,
    int? ttl,
    int? totalPeople,
    String? description,
  }) {
    return SosPacketMessage(
      packetId: packetId,
      sosId: sosId,
      originDeviceId: originDeviceId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      hopCount: hopCount ?? this.hopCount,
      ttl: ttl ?? this.ttl,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      totalPeople: totalPeople ?? this.totalPeople,
      childrenCount: childrenCount,
      elderlyCount: elderlyCount,
      pregnantWomenCount: pregnantWomenCount,
      specialAssistanceCount: specialAssistanceCount,
      emergencyType: emergencyType,
      description: description ?? this.description,
      priority: priority,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
        'type': 'SOS',
        'packetId': packetId,
        'sosId': sosId,
        'originDeviceId': originDeviceId,
        'senderDeviceId': senderDeviceId,
        'hopCount': hopCount,
        'ttl': ttl,
        'timestamp': formatUtc(timestamp),
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'totalPeople': totalPeople,
        'childrenCount': childrenCount,
        'elderlyCount': elderlyCount,
        'pregnantWomenCount': pregnantWomenCount,
        'specialAssistanceCount': specialAssistanceCount,
        'emergencyType': emergencyType.code,
        'description': description,
        'priority': priority.code,
      };
}

class AckPacketMessage extends BlePacketMessage {
  const AckPacketMessage({
    required super.packetId,
    required super.sosId,
    required super.originDeviceId,
    required super.senderDeviceId,
    required super.hopCount,
    required super.ttl,
    required super.timestamp,
    required super.latitude,
    required super.longitude,
    super.accuracy,
  });

  @override
  AckPacketMessage copyWith({
    String? senderDeviceId,
    int? hopCount,
    int? ttl,
  }) {
    return AckPacketMessage(
      packetId: packetId,
      sosId: sosId,
      originDeviceId: originDeviceId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      hopCount: hopCount ?? this.hopCount,
      ttl: ttl ?? this.ttl,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
        'type': 'ACK',
        'packetId': packetId,
        'sosId': sosId,
        'originDeviceId': originDeviceId,
        'senderDeviceId': senderDeviceId,
        'hopCount': hopCount,
        'ttl': ttl,
        'timestamp': formatUtc(timestamp),
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
      };
}