/// Packet persistence: known packets, pending transmissions and a bounded
/// duplicate cache.
///
/// All three concerns live here so the routing layer stays storage-agnostic
/// and the duplicate cache can be shared/pruned in one place.
library;

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/time_format.dart';
import '../models/enums/emergency_type.dart';
import '../models/enums/sos_priority.dart';
import '../models/sos_packet.dart';

abstract class PacketRepository {
  Stream<List<BlePacketMessage>> watchPackets();
  Future<List<BlePacketMessage>> getPackets();
  Future<void> savePacket(BlePacketMessage packet);

  /// Whether [packetId] was already processed (bounded duplicate cache).
  Future<bool> isDuplicate(String packetId);

  /// Record a packet id as seen, pruning the cache when it overflows.
  Future<void> recordSeen(String packetId, DateTime at);

  Future<List<String>> pendingPacketIds();
  Future<void> markPending(String packetId);
  Future<void> markPendingResolved(String packetId);
  Stream<void> watchPending();

  /// Drops packets, queued transmissions and the duplicate cache.
  /// Returns `(packetsRemoved, pendingRemoved)`.
  Future<(int, int)> clear();
}

class HivePacketRepository implements PacketRepository {
  HivePacketRepository(this._packetsBox, this._outboxBox, this._dupBox);

  final Box _packetsBox;
  final Box _outboxBox;
  final Box _dupBox;

  List<BlePacketMessage> _readAll() {
    final result = <BlePacketMessage>[];
    for (final value in _packetsBox.values) {
      final parsed = PacketCodecLite.decodeMap(value);
      if (parsed != null) result.add(parsed);
    }
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  @override
  Stream<List<BlePacketMessage>> watchPackets() {
    // Broadcast streams drop pre-subscription events and Hive's `Box.watch()`
    // only fires on writes, so emit the current snapshot from `onListen`.
    late final StreamController<List<BlePacketMessage>> controller;
    StreamSubscription<BoxEvent>? sub;
    controller = StreamController<List<BlePacketMessage>>.broadcast(
      onListen: () {
        controller.add(_readAll());
        sub = _packetsBox.watch().listen((_) {
          if (!controller.isClosed) controller.add(_readAll());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<List<BlePacketMessage>> getPackets() async => _readAll();

  @override
  Future<void> savePacket(BlePacketMessage packet) async {
    await _packetsBox.put(packet.packetId, packet.toMap());
  }

  @override
  Future<bool> isDuplicate(String packetId) async =>
      _dupBox.containsKey(packetId);

  @override
  Future<void> recordSeen(String packetId, DateTime at) async {
    if (_dupBox.length >= BleConstants.dupCacheCapacity) {
      await _pruneDupCache();
    }
    await _dupBox.put(packetId, formatUtc(at));
  }

  Future<void> _pruneDupCache() async {
    final cutoff =
        DateTime.now().toUtc().subtract(BleConstants.dupCacheRetention);
    final toDelete = <dynamic>[];
    _dupBox.toMap().forEach((key, value) {
      final at = parseUtc(value?.toString());
      if (at == null || at.isBefore(cutoff)) {
        toDelete.add(key);
      }
    });
    for (final key in toDelete) {
      await _dupBox.delete(key);
    }
  }

  @override
  Future<List<String>> pendingPacketIds() async =>
      _outboxBox.keys.cast<String>().toList();

  @override
  Future<void> markPending(String packetId) async {
    await _outboxBox.put(packetId, formatUtc(DateTime.now().toUtc()));
  }

  @override
  Future<void> markPendingResolved(String packetId) async {
    await _outboxBox.delete(packetId);
  }

  @override
  Stream<void> watchPending() {
    late final StreamController<void> controller;
    StreamSubscription<BoxEvent>? sub;
    controller = StreamController<void>.broadcast(
      onListen: () {
        controller.add(null);
        sub = _outboxBox.watch().listen((_) {
          if (!controller.isClosed) controller.add(null);
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<(int, int)> clear() async {
    final packets = _packetsBox.length;
    final pending = _outboxBox.length;
    await _packetsBox.clear();
    await _outboxBox.clear();
    await _dupBox.clear();
    return (packets, pending);
  }
}

/// Tiny standalone decoder used by the repository layer to avoid importing
/// the full routing codec. Produces the exact models defined in
/// `models/sos_packet.dart`.
class PacketCodecLite {
  PacketCodecLite._();

  static BlePacketMessage? decodeMap(dynamic rawMap) {
    if (rawMap is! Map) return null;
    final m = Map<String, dynamic>.from(rawMap);
    try {
      final type = m['type'];
      final timestamp = parseUtc(m['timestamp']?.toString());
      if (timestamp == null) return null;
      if (type == 'SOS') {
        return SosPacketMessage(
          packetId: m['packetId']?.toString() ?? '',
          sosId: m['sosId']?.toString() ?? '',
          originDeviceId: m['originDeviceId']?.toString() ?? '',
          senderDeviceId: m['senderDeviceId']?.toString() ?? '',
          hopCount: (m['hopCount'] as num?)?.toInt() ?? 0,
          ttl: (m['ttl'] as num?)?.toInt() ?? 0,
          timestamp: timestamp,
          latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
          accuracy: (m['accuracy'] as num?)?.toDouble(),
          totalPeople: (m['totalPeople'] as num?)?.toInt() ?? 0,
          childrenCount: (m['childrenCount'] as num?)?.toInt() ?? 0,
          elderlyCount: (m['elderlyCount'] as num?)?.toInt() ?? 0,
          pregnantWomenCount: (m['pregnantWomenCount'] as num?)?.toInt() ?? 0,
          specialAssistanceCount: (m['specialAssistanceCount'] as num?)?.toInt() ?? 0,
          emergencyType:
              EmergencyType.fromCode(m['emergencyType']?.toString()) ??
                  EmergencyType.other,
          description: m['description']?.toString() ?? '',
          priority: SosPriority.fromCode(m['priority']?.toString()) ??
              SosPriority.low,
        );
      }
      if (type == 'ACK') {
        return AckPacketMessage(
          packetId: m['packetId']?.toString() ?? '',
          sosId: m['sosId']?.toString() ?? '',
          originDeviceId: m['originDeviceId']?.toString() ?? '',
          senderDeviceId: m['senderDeviceId']?.toString() ?? '',
          hopCount: (m['hopCount'] as num?)?.toInt() ?? 0,
          ttl: (m['ttl'] as num?)?.toInt() ?? 0,
          timestamp: timestamp,
          latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
          accuracy: (m['accuracy'] as num?)?.toDouble(),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

/// In-memory packet repository used by tests and the demo mesh. It shares the
/// same interface as the persisted implementation so routing code never knows
/// the difference.
class MemoryPacketRepository implements PacketRepository {
  final Map<String, BlePacketMessage> _packets = {};
  final Map<String, String> _pending = {};
  final Map<String, DateTime> _duplicates = {};
  final StreamController<List<BlePacketMessage>> _controller =
      StreamController<List<BlePacketMessage>>.broadcast();
  final StreamController<void> _pendingController =
      StreamController<void>.broadcast();

  @override
  Stream<List<BlePacketMessage>> watchPackets() {
    _controller.add(getPacketsSync());
    return _controller.stream;
  }

  List<BlePacketMessage> getPacketsSync() {
    final list = _packets.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Future<List<BlePacketMessage>> getPackets() async => getPacketsSync();

  @override
  Future<void> savePacket(BlePacketMessage packet) async {
    _packets[packet.packetId] = packet;
    if (!_controller.isClosed) _controller.add(getPacketsSync());
  }

  @override
  Future<bool> isDuplicate(String packetId) async =>
      _duplicates.containsKey(packetId);

  @override
  Future<void> recordSeen(String packetId, DateTime at) async {
    if (_duplicates.length >= BleConstants.dupCacheCapacity) {
      _duplicates.removeWhere((_, v) =>
          v.isBefore(DateTime.now().toUtc().subtract(BleConstants.dupCacheRetention)));
    }
    _duplicates[packetId] = at;
  }

  @override
  Future<List<String>> pendingPacketIds() async => _pending.keys.toList();

  @override
  Future<void> markPending(String packetId) async {
    _pending[packetId] = formatUtc(DateTime.now().toUtc());
    if (!_pendingController.isClosed) _pendingController.add(null);
  }

  @override
  Future<void> markPendingResolved(String packetId) async {
    _pending.remove(packetId);
    if (!_pendingController.isClosed) _pendingController.add(null);
  }

  @override
  Stream<void> watchPending() => _pendingController.stream;

  @override
  Future<(int, int)> clear() async {
    final removed = (_packets.length, _pending.length);
    _packets.clear();
    _pending.clear();
    _duplicates.clear();
    if (!_controller.isClosed) _controller.add(getPacketsSync());
    if (!_pendingController.isClosed) _pendingController.add(null);
    return removed;
  }

  void dispose() {
    _controller.close();
    _pendingController.close();
  }
}