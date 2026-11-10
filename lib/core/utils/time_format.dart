/// Time formatting helpers used across the UI.
library;

String _pad(int n) => n.toString().padLeft(2, '0');

/// Serialize a [DateTime] losslessly as an ISO-8601 UTC string.
String formatUtc(DateTime time) {
  final t = time.toUtc();
  return '${t.year}-${_pad(t.month)}-${_pad(t.day)}T'
      '${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}Z';
}

/// Parse an ISO-8601 UTC string produced by [formatUtc].
///
/// Returns null when parsing fails.
DateTime? parseUtc(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

/// Human friendly relative time ("just now", "5m ago", "2026-09-22").
String formatRelative(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time.toLocal());
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final t = time.toLocal();
  return '${t.year}-${_pad(t.month)}-${_pad(t.day)}';
}

/// Full timestamp for details screens.
String formatFull(DateTime time) {
  final t = time.toLocal();
  return '${t.year}-${_pad(t.month)}-${_pad(t.day)} '
      '${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}';
}