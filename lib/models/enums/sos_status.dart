/// SOS lifecycle status.
///
/// Transitions are validated by [canTransitionTo]. `resolved` is terminal.
library;

enum SosStatus {
  pending('PENDING', 'Pending'),
  acknowledged('ACKNOWLEDGED', 'Acknowledged'),
  rescueAssigned('RESCUE_ASSIGNED', 'Rescue Assigned'),
  inProgress('IN_PROGRESS', 'In Progress'),
  resolved('RESOLVED', 'Resolved');

  const SosStatus(this.code, this.label);

  final String code;
  final String label;

  /// Allowed transitions from this status to [next].
  bool canTransitionTo(SosStatus next) => allowedTransitions.contains(next);

  Set<SosStatus> get allowedTransitions => switch (this) {
        SosStatus.pending => {
            SosStatus.acknowledged,
            SosStatus.inProgress,
          },
        SosStatus.acknowledged => {
            SosStatus.rescueAssigned,
            SosStatus.inProgress,
          },
        SosStatus.rescueAssigned => {SosStatus.inProgress},
        SosStatus.inProgress => {SosStatus.resolved},
        SosStatus.resolved => {},
      };

  /// Whether this status represents an emergency that still needs attention.
  bool get isActive => this != SosStatus.resolved;

  static SosStatus? fromCode(String? code) {
    if (code == null) return null;
    for (final s in SosStatus.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}