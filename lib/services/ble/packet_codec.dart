/// Packet codec: deterministic serialization, deserialization and validation
/// for SOS and ACK packets.
///
/// Serialization is deterministic: maps are constructed in a fixed field
/// order so the same packet always produces the same JSON bytes.
library;

import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_format.dart';
import '../../models/enums/emergency_type.dart';
import '../../models/enums/sos_priority.dart';
import '../../models/sos_packet.dart';

enum PacketValidationReason {
  notJson,
  missingType,
  unknownType,
  badPacketId,
  badSosId,
  badDeviceId,
  badTimestamps,
  expiredPacket,
  futurePacket,
  badCoordinates,
  badTtlOrHop,
  badPeopleCounts,
  badEmergencyType,
  badPriority,
  payloadTooLarge,
}

String packetValidationMessage(PacketValidationReason reason) => switch (reason) {
      PacketValidationReason.notJson => 'Packet is not valid JSON.',
      PacketValidationReason.missingType => 'Packet has no type field.',
      PacketValidationReason.unknownType => 'Packet type must be SOS or ACK.',
      PacketValidationReason.badPacketId => 'Packet id is malformed.',
      PacketValidationReason.badSosId => 'SOS id is malformed.',
      PacketValidationReason.badDeviceId => 'Device id is malformed.',
      PacketValidationReason.badTimestamps => 'Timestamp is malformed.',
      PacketValidationReason.expiredPacket => 'Packet is outside the replay window.',
      PacketValidationReason.futurePacket => 'Packet timestamp is in the future.',
      PacketValidationReason.badCoordinates => 'Coordinates are out of range.',
      PacketValidationReason.badTtlOrHop => 'TTL or hop count is out of range.',
      PacketValidationReason.badPeopleCounts => 'People counts are invalid.',
      PacketValidationReason.badEmergencyType => 'Emergency type is unknown.',
      PacketValidationReason.badPriority => 'Priority is unknown.',
      PacketValidationReason.payloadTooLarge => 'Packet payload is too large.',
    };

class PacketCodec {
  const PacketCodec({DateTime Function()? now})
      : _now = now ?? _defaultNow;

  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  static const int maxPacketBytes = 2048;

  /// Deterministic serialization.
  String encode(BlePacketMessage message) => jsonEncode(message.toMap());

  /// Parse and validate [raw]. Throws [PacketValidationError] with a
  /// [PacketValidationReason] when the payload is not acceptable.
  BlePacketMessage decode(String raw) {
    if (raw.length > maxPacketBytes) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.payloadTooLarge),
      );
    }

    Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.notJson),
      );
    }
    if (json is! Map) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.notJson),
      );
    }
    final m = Map<String, dynamic>.from(json);

    final type = m['type'];
    if (type == null) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.missingType),
      );
    }

    final packetId = _str(m, 'packetId');
    final sosId = _str(m, 'sosId');
    final originDeviceId = _str(m, 'originDeviceId');
    final senderDeviceId = _str(m, 'senderDeviceId');
    final rawTimestamp = _str(m, 'timestamp');
    final hop = _int(m, 'hopCount') ?? 0;
    final ttl = _int(m, 'ttl') ?? 0;
    final latitude = _double(m, 'latitude');
    final longitude = _double(m, 'longitude');
    final accuracy = _double(m, 'accuracy');

    _validateCommon(
      packetId: packetId,
      sosId: sosId,
      originDeviceId: originDeviceId,
      senderDeviceId: senderDeviceId,
      rawTimestamp: rawTimestamp,
      hop: hop,
      ttl: ttl,
      latitude: latitude,
      longitude: longitude,
    );
    final timestamp = parseUtc(rawTimestamp)!;

    if (type == 'SOS') {
      final total = _int(m, 'totalPeople') ?? 0;
      final children = _int(m, 'childrenCount') ?? 0;
      final elderly = _int(m, 'elderlyCount') ?? 0;
      final pregnant = _int(m, 'pregnantWomenCount') ?? 0;
      final special = _int(m, 'specialAssistanceCount') ?? 0;
      final summarized = children + elderly + pregnant + special;
      if (total != 0 && total < 1) {
        throw PacketValidationError(
          packetValidationMessage(PacketValidationReason.badPeopleCounts),
        );
      }
      if (children < 0 ||
          elderly < 0 ||
          pregnant < 0 ||
          special < 0 ||
          summarized > total) {
        throw PacketValidationError(
          packetValidationMessage(PacketValidationReason.badPeopleCounts),
        );
      }
      final emergencyType = EmergencyType.fromCode(_str(m, 'emergencyType'));
      if (emergencyType == null) {
        throw PacketValidationError(
          packetValidationMessage(PacketValidationReason.badEmergencyType),
        );
      }
      final priority = SosPriority.fromCode(_str(m, 'priority'));
      if (priority == null) {
        throw PacketValidationError(
          packetValidationMessage(PacketValidationReason.badPriority),
        );
      }
      final description = _str(m, 'description');
      if (description.length > Limits.maxDescriptionLength) {
        throw PacketValidationError(
          packetValidationMessage(PacketValidationReason.payloadTooLarge),
        );
      }
      return SosPacketMessage(
        packetId: packetId,
        sosId: sosId,
        originDeviceId: originDeviceId,
        senderDeviceId: senderDeviceId,
        hopCount: hop,
        ttl: ttl,
        timestamp: timestamp,
        latitude: latitude!,
        longitude: longitude!,
        accuracy: accuracy,
        totalPeople: total,
        childrenCount: children,
        elderlyCount: elderly,
        pregnantWomenCount: pregnant,
        specialAssistanceCount: special,
        emergencyType: emergencyType,
        description: description,
        priority: priority,
      );
    }

    if (type == 'ACK') {
      return AckPacketMessage(
        packetId: packetId,
        sosId: sosId,
        originDeviceId: originDeviceId,
        senderDeviceId: senderDeviceId,
        hopCount: hop,
        ttl: ttl,
        timestamp: timestamp,
        latitude: latitude!,
        longitude: longitude!,
        accuracy: accuracy,
      );
    }

    throw PacketValidationError(
      packetValidationMessage(PacketValidationReason.unknownType),
    );
  }

  void _validateCommon({
    required String packetId,
    required String sosId,
    required String originDeviceId,
    required String senderDeviceId,
    required String rawTimestamp,
    required int hop,
    required int ttl,
    required double? latitude,
    required double? longitude,
  }) {
    final validPacketId =
        IdGenerator.packetIdPattern.hasMatch(packetId) ||
            IdGenerator.ackIdPattern.hasMatch(packetId);
    if (!validPacketId) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badPacketId),
      );
    }
    if (!IdGenerator.sosIdPattern.hasMatch(sosId)) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badSosId),
      );
    }
    // The sender may be unknown at the link layer; empty is not allowed for
    // a routed packet.
    if (originDeviceId.isEmpty || senderDeviceId.isEmpty) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badDeviceId),
      );
    }
    if (rawTimestamp.isEmpty || parseUtc(rawTimestamp) == null) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badTimestamps),
      );
    }
    final now = _now().toUtc();
    final timestamp = parseUtc(rawTimestamp);
    if (timestamp!.isBefore(now.subtract(BleConstants.replayWindow))) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.expiredPacket),
      );
    }
    if (timestamp.isAfter(now.add(BleConstants.futureSkew))) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.futurePacket),
      );
    }
    if (ttl < 1 || ttl > BleConstants.maxHops) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badTtlOrHop),
      );
    }
    if (hop < 0 || hop >= BleConstants.maxHops) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badTtlOrHop),
      );
    }
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw PacketValidationError(
        packetValidationMessage(PacketValidationReason.badCoordinates),
      );
    }
  }

  static String _str(Map<String, dynamic> m, String key) =>
      m[key]?.toString() ?? '';

  static int? _int(Map<String, dynamic> m, String key) {
    final v = m[key];
    return v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
  }

  static double? _double(Map<String, dynamic> m, String key) {
    final v = m[key];
    return v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  }
}