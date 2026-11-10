/// Kinds of assistance a civilian can request.
library;

enum HelpCategory {
  rescue('RESCUE', 'Rescue'),
  food('FOOD', 'Food'),
  drinkingWater('DRINKING_WATER', 'Drinking water'),
  medical('MEDICAL', 'Medical assistance'),
  shelter('SHELTER', 'Shelter'),
  transport('TRANSPORTATION', 'Transportation'),
  other('OTHER', 'Other');

  const HelpCategory(this.code, this.label);

  final String code;
  final String label;

  static HelpCategory? fromCode(String? code) {
    if (code == null) return null;
    for (final c in HelpCategory.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Urgency of a help request.
enum HelpPriority {
  low('LOW', 'Low', 0),
  medium('MEDIUM', 'Medium', 1),
  high('HIGH', 'High', 2),
  urgent('URGENT', 'Urgent', 3);

  const HelpPriority(this.code, this.label, this.weight);

  final String code;
  final String label;
  final int weight;

  static HelpPriority? fromCode(String? code) {
    if (code == null) return null;
    for (final p in HelpPriority.values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Lifecycle of a help request once it has been filed.
enum HelpRequestStatus {
  pending('PENDING', 'Pending'),
  acknowledged('ACKNOWLEDGED', 'Acknowledged'),
  inProgress('IN_PROGRESS', 'In progress'),
  fulfilled('FULFILLED', 'Fulfilled'),
  cancelled('CANCELLED', 'Cancelled');

  const HelpRequestStatus(this.code, this.label);

  final String code;
  final String label;

  bool get isOpen =>
      this == pending || this == acknowledged || this == inProgress;

  static HelpRequestStatus? fromCode(String? code) {
    if (code == null) return null;
    for (final s in HelpRequestStatus.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}
