/// Occupancy state of a shelter / safe location.
library;

enum ShelterStatus {
  available('AVAILABLE', 'Space available'),
  limited('LIMITED', 'Almost full'),
  full('FULL', 'Full');

  const ShelterStatus(this.code, this.label);

  final String code;
  final String label;

  static ShelterStatus? fromCode(String? code) {
    if (code == null) return null;
    for (final s in ShelterStatus.values) {
      if (s.code == code) return s;
    }
    return null;
  }

  /// Derives the occupancy state from a capacity pair so the two can never
  /// contradict each other in storage.
  static ShelterStatus fromCapacity({
    required int capacity,
    required int occupied,
  }) {
    if (capacity <= 0) return ShelterStatus.limited;
    if (occupied >= capacity) return ShelterStatus.full;
    if (occupied * 2 >= capacity) return ShelterStatus.limited;
    return ShelterStatus.available;
  }
}
