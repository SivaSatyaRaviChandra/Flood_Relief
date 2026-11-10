/// Severity banding used for alerts and on-site banners.
library;

enum AlertSeverity {
  info('INFO', 'Info', 0),
  warning('WARNING', 'Warning', 1),
  danger('DANGER', 'Danger', 2),
  critical('CRITICAL', 'Critical', 3);

  const AlertSeverity(this.code, this.label, this.weight);

  final String code;
  final String label;
  final int weight;

  static AlertSeverity? fromCode(String? code) {
    if (code == null) return null;
    for (final s in AlertSeverity.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}
