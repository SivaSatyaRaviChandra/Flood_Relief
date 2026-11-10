/// SOS priority levels, ordered from most to least severe.
library;

enum SosPriority {
  low('LOW', 'Low', 0),
  medium('MEDIUM', 'Medium', 1),
  high('HIGH', 'High', 2),
  critical('CRITICAL', 'Critical', 3);

  const SosPriority(this.code, this.label, this.weight);

  final String code;
  final String label;
  final int weight;

  static SosPriority? fromCode(String? code) {
    if (code == null) return null;
    for (final p in SosPriority.values) {
      if (p.code == code) return p;
    }
    return null;
  }
}