/// Robust casting helpers for values read back from Hive or JSON.
///
/// Hive stores what you put in; JSON may hand back `num` instead of `int` /
/// `double`. These helpers centralize coercion and null handling.
library;

int? asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? asDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool asBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true';
  return fallback;
}

String asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}