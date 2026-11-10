/// Rescue team availability.
library;

enum TeamStatus {
  available('AVAILABLE', 'Available'),
  responding('RESPONDING', 'Responding'),
  inField('IN_FIELD', 'In the field'),
  unavailable('UNAVAILABLE', 'Unavailable');

  const TeamStatus(this.code, this.label);

  final String code;
  final String label;

  static TeamStatus? fromCode(String? code) {
    if (code == null) return null;
    for (final s in TeamStatus.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}