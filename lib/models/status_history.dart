/// One entry in an SOS' status history.
///
/// Every transition records the previous status, the new status, the time of
/// the change and an optional actor (user id or rescue team id).
library;

import '../core/utils/cast.dart';
import '../core/utils/time_format.dart';
import 'enums/sos_status.dart';

class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.newStatus,
    this.previousStatus,
    required this.timestamp,
    this.actorId,
    this.teamId,
    this.note,
  });

  final SosStatus? previousStatus;
  final SosStatus newStatus;
  final DateTime timestamp;
  final String? actorId;
  final String? teamId;
  final String? note;

  StatusHistoryEntry copyWith({
    SosStatus? previousStatus,
    SosStatus? newStatus,
    DateTime? timestamp,
    String? actorId,
    String? teamId,
    String? note,
  }) {
    return StatusHistoryEntry(
      previousStatus: previousStatus ?? this.previousStatus,
      newStatus: newStatus ?? this.newStatus,
      timestamp: timestamp ?? this.timestamp,
      actorId: actorId ?? this.actorId,
      teamId: teamId ?? this.teamId,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() => {
        'previousStatus': previousStatus?.code,
        'newStatus': newStatus.code,
        'timestamp': formatUtc(timestamp),
        if (actorId != null) 'actorId': actorId,
        if (teamId != null) 'teamId': teamId,
        if (note != null) 'note': note,
      };

  static StatusHistoryEntry fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return StatusHistoryEntry(
      previousStatus: SosStatus.fromCode(asString(m['previousStatus'], fallback: '')),
      newStatus:
          SosStatus.fromCode(asString(m['newStatus'])) ?? SosStatus.pending,
      timestamp:
          parseUtc(asString(m['timestamp'])) ?? DateTime.now().toUtc(),
      actorId: asString(m['actorId'], fallback: '') == ''
          ? null
          : asString(m['actorId']),
      teamId: asString(m['teamId'], fallback: '') == ''
          ? null
          : asString(m['teamId']),
      note: asString(m['note'], fallback: '') == '' ? null : asString(m['note']),
    );
  }
}