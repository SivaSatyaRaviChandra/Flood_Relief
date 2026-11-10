/// Packet codec: deterministic encode/decode, validation and replay rules.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/core/errors/app_error.dart';
import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/sos_packet.dart';
import 'package:flood_relief/repositories/packet_repository.dart';
import 'package:flood_relief/services/ble/packet_codec.dart';

final DateTime fixedNow = DateTime.utc(2026, 9, 22, 12, 0, 0);
final codec = PacketCodec(now: () => fixedNow);

SosPacketMessage _sosPacket({DateTime? at, int ttl = 8, int hop = 0}) {
  return SosPacketMessage(
    packetId: 'PKT-ABCD1234',
    sosId: 'SOS-20260922-ABCDEF',
    originDeviceId: 'DEVICE-ORIG1234',
    senderDeviceId: 'DEVICE-SEND1234',
    hopCount: hop,
    ttl: ttl,
    timestamp: at ?? fixedNow,
    latitude: 17.7,
    longitude: 83.3,
    accuracy: 12.0,
    totalPeople: 4,
    childrenCount: 1,
    elderlyCount: 1,
    pregnantWomenCount: 0,
    specialAssistanceCount: 0,
    emergencyType: EmergencyType.rescueRequired,
    description: 'Water rising.',
    priority: SosPriority.high,
  );
}

AckPacketMessage _ackPacket({DateTime? at}) {
  return AckPacketMessage(
    packetId: 'PKT-ABCD1234',
    sosId: 'SOS-20260922-ABCDEF',
    originDeviceId: 'DEVICE-RESCUE',
    senderDeviceId: 'DEVICE-RELAY00',
    hopCount: 1,
    ttl: 7,
    timestamp: at ?? fixedNow,
    latitude: 17.7,
    longitude: 83.3,
    accuracy: 20.0,
  );
}

Map<String, dynamic> _baseMap({String type = 'SOS', String? timestamp}) => {
      'type': type,
      'packetId': 'PKT-ABCD1234',
      'sosId': 'SOS-20260922-ABCDEF',
      'originDeviceId': 'DEVICE-ORIG1234',
      'senderDeviceId': 'DEVICE-SEND1234',
      'hopCount': 0,
      'ttl': 8,
      'timestamp': timestamp ?? '2026-09-22T12:00:00.000Z',
      'latitude': 17.7,
      'longitude': 83.3,
      'accuracy': 12.0,
      'totalPeople': 4,
      'childrenCount': 1,
      'elderlyCount': 1,
      'pregnantWomenCount': 0,
      'specialAssistanceCount': 0,
      'emergencyType': 'RESCUE_REQUIRED',
      'description': 'Water rising.',
      'priority': 'HIGH',
    };

void main() {
  group('encode/decode', () {
    test('SOS packets round-trip losslessly', () {
      final encoded = codec.encode(_sosPacket());
      final decoded = codec.decode(encoded);
      expect(decoded, isA<SosPacketMessage>());
      final sos = decoded as SosPacketMessage;
      expect(sos.packetId, 'PKT-ABCD1234');
      expect(sos.sosId, 'SOS-20260922-ABCDEF');
      expect(sos.hopCount, 0);
      expect(sos.ttl, 8);
      expect(sos.timestamp, fixedNow);
      expect(sos.latitude, 17.7);
      expect(sos.totalPeople, 4);
      expect(sos.childrenCount, 1);
      expect(sos.emergencyType, EmergencyType.rescueRequired);
      expect(sos.priority, SosPriority.high);
    });

    test('ACK packets round-trip losslessly', () {
      final decoded = codec.decode(codec.encode(_ackPacket()));
      expect(decoded, isA<AckPacketMessage>());
      final ack = decoded as AckPacketMessage;
      expect(ack.sosId, 'SOS-20260922-ABCDEF');
      expect(ack.originDeviceId, 'DEVICE-RESCUE');
      expect(ack.hopCount, 1);
      expect(ack.ttl, 7);
    });

    test('serialization is deterministic', () {
      final a = codec.encode(_sosPacket());
      final b = codec.encode(_sosPacket());
      expect(a, b);
    });

    test('PacketCodecLite decodes stored maps', () {
      final packet = _sosPacket();
      final restored = PacketCodecLite.decodeMap(packet.toMap());
      expect(restored, isA<SosPacketMessage>());
      expect((restored as SosPacketMessage).sosId, packet.sosId);
      expect(restored.priority, SosPriority.high);
      expect(PacketCodecLite.decodeMap(_ackPacket().toMap()),
          isA<AckPacketMessage>());
      expect(PacketCodecLite.decodeMap('nope'), isNull);
    });
  });

  group('validation failures', () {
    void expectReason(Map<String, dynamic> map, PacketValidationReason reason) {
      try {
        codec.decode(jsonEncode(map));
        fail('expected a PacketValidationError for $reason');
      } on PacketValidationError catch (e) {
        expect(e.reason, packetValidationMessage(reason));
      }
    }

    test('non-JSON payload', () {
      // A JSON object without a type field is parseable JSON, so it fails the
      // type check first rather than the syntax check.
      expectReason({'bogus': true}, PacketValidationReason.missingType);
      try {
        codec.decode('not json at all');
        fail('expected a PacketValidationError');
      } on PacketValidationError catch (e) {
        expect(e.reason, packetValidationMessage(PacketValidationReason.notJson));
      }
    });

    test('missing and unknown type', () {
      final noType = _baseMap()..remove('type');
      expectReason(noType, PacketValidationReason.missingType);
      expectReason(_baseMap(type: 'PING'), PacketValidationReason.unknownType);
    });

    test('malformed ids and devices', () {
      final badPacket = _baseMap()..['packetId'] = 'nope';
      expectReason(badPacket, PacketValidationReason.badPacketId);

      final badSos = _baseMap()..['sosId'] = 'SOS-x';
      expectReason(badSos, PacketValidationReason.badSosId);

      final noOrigin = _baseMap()..['originDeviceId'] = '';
      expectReason(noOrigin, PacketValidationReason.badDeviceId);
    });

    test('timestamps: malformed, expired and in the future', () {
      final badTime = _baseMap()..['timestamp'] = 'garbage';
      expectReason(badTime, PacketValidationReason.badTimestamps);

      final expired = _baseMap()
        ..['timestamp'] = '2026-09-22T05:00:00.000Z';
      expectReason(expired, PacketValidationReason.expiredPacket);

      final future = _baseMap()
        ..['timestamp'] = '2026-09-22T12:30:00.000Z';
      expectReason(future, PacketValidationReason.futurePacket);
    });

    test('coordinates out of range', () {
      final bad = _baseMap()..['latitude'] = 91.0;
      expectReason(bad, PacketValidationReason.badCoordinates);
    });

    test('TTL and hop bounds', () {
      final noTtl = _baseMap()..['ttl'] = 0;
      expectReason(noTtl, PacketValidationReason.badTtlOrHop);

      final tooManyHops = _baseMap()..['hopCount'] = 8;
      expectReason(tooManyHops, PacketValidationReason.badTtlOrHop);
    });

    test('people counts must be coherent', () {
      final bad = _baseMap()..['childrenCount'] = 9;
      expectReason(bad, PacketValidationReason.badPeopleCounts);
    });

    test('unknown emergency type or priority', () {
      final badType = _baseMap()..['emergencyType'] = 'METEOR';
      expectReason(badType, PacketValidationReason.badEmergencyType);

      final badPriority = _baseMap()..['priority'] = 'URGENT';
      expectReason(badPriority, PacketValidationReason.badPriority);
    });

    test('oversized payload is rejected up front', () {
      final big = 'x' * (PacketCodec.maxPacketBytes + 1);
      try {
        codec.decode(big);
        fail('expected a PacketValidationError');
      } on PacketValidationError catch (e) {
        expect(
            e.reason, packetValidationMessage(PacketValidationReason.payloadTooLarge));
      }
    });
  });
}