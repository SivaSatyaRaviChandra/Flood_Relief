/// People counts for an SOS.
///
/// Intentionally a single immutable value object so validation lives in one
/// place and is unit-testable.
library;

class PeopleInfo {
  const PeopleInfo({
    this.totalPeople = 0,
    this.childrenCount = 0,
    this.elderlyCount = 0,
    this.pregnantWomenCount = 0,
    this.specialAssistanceCount = 0,
  });

  final int totalPeople;
  final int childrenCount;
  final int elderlyCount;
  final int pregnantWomenCount;
  final int specialAssistanceCount;

  int get categorizedSum =>
      childrenCount + elderlyCount + pregnantWomenCount + specialAssistanceCount;

  PeopleInfo copyWith({
    int? totalPeople,
    int? childrenCount,
    int? elderlyCount,
    int? pregnantWomenCount,
    int? specialAssistanceCount,
  }) {
    return PeopleInfo(
      totalPeople: totalPeople ?? this.totalPeople,
      childrenCount: childrenCount ?? this.childrenCount,
      elderlyCount: elderlyCount ?? this.elderlyCount,
      pregnantWomenCount: pregnantWomenCount ?? this.pregnantWomenCount,
      specialAssistanceCount: specialAssistanceCount ?? this.specialAssistanceCount,
    );
  }

  /// Validation rules:
  /// * all counts are non-negative;
  /// * each category cannot exceed the total;
  /// * the sum of the four categories cannot exceed the total (each affected
  ///   person is counted in at most one category).
  ///
  /// Returns an empty list when valid.
  List<String> validate() {
    final errors = <String>[];
    if (totalPeople < 0) errors.add('Total people cannot be negative.');
    if (childrenCount < 0) errors.add('Children count cannot be negative.');
    if (elderlyCount < 0) errors.add('Elderly count cannot be negative.');
    if (pregnantWomenCount < 0) {
      errors.add('Pregnant women count cannot be negative.');
    }
    if (specialAssistanceCount < 0) {
      errors.add('Special assistance count cannot be negative.');
    }
    if (categorizedSum > totalPeople) {
      errors.add(
        'Categorized counts (children + elderly + pregnant + special = '
        '$categorizedSum) cannot exceed the total of $totalPeople people.',
      );
    }
    return errors;
  }

  Map<String, dynamic> toMap() => {
        'totalPeople': totalPeople,
        'childrenCount': childrenCount,
        'elderlyCount': elderlyCount,
        'pregnantWomenCount': pregnantWomenCount,
        'specialAssistanceCount': specialAssistanceCount,
      };

  static PeopleInfo fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return PeopleInfo(
      totalPeople: (m['totalPeople'] as num?)?.toInt() ?? 0,
      childrenCount: (m['childrenCount'] as num?)?.toInt() ?? 0,
      elderlyCount: (m['elderlyCount'] as num?)?.toInt() ?? 0,
      pregnantWomenCount: (m['pregnantWomenCount'] as num?)?.toInt() ?? 0,
      specialAssistanceCount:
          (m['specialAssistanceCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'PeopleInfo(total: $totalPeople, children: $childrenCount, '
      'elderly: $elderlyCount, pregnant: $pregnantWomenCount, '
      'special: $specialAssistanceCount)';
}